defmodule Jido.Document.Agent do
  @moduledoc """
  Stateful document session process.

  The agent is the source of truth for active document, preview, history,
  subscribers, and concurrency locks. It orchestrates action execution and
  emits lifecycle signals through `Jido.Document.SignalBus`.
  """

  use GenServer

  alias Jido.Document.Action
  alias Jido.Document.Action.Result
  alias Jido.Document.{Document, Error, SignalBus}

  @type action_name :: :load | :save | :update_frontmatter | :update_body | :render

  @type history_entry :: %{
          action: action_name(),
          revision: non_neg_integer() | nil,
          timestamp: DateTime.t(),
          correlation_id: String.t() | nil
        }

  @type state :: %__MODULE__{
          session_id: String.t(),
          document: Document.t() | nil,
          disk_snapshot: map() | nil,
          preview: map() | nil,
          last_good_preview: map() | nil,
          render_fallback_active: boolean(),
          history: [history_entry()],
          subscribers: MapSet.t(pid()),
          locks: MapSet.t(atom()),
          signal_bus: GenServer.server()
        }

  defstruct session_id: nil,
            document: nil,
            disk_snapshot: nil,
            preview: nil,
            last_good_preview: nil,
            render_fallback_active: false,
            history: [],
            subscribers: MapSet.new(),
            locks: MapSet.new(),
            signal_bus: SignalBus

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @spec command(GenServer.server(), action_name(), map() | keyword(), keyword()) ::
          Result.t() | :ok
  def command(server, action, params \\ %{}, opts \\ []) do
    mode = Keyword.get(opts, :mode, :sync)

    case mode do
      :sync ->
        GenServer.call(server, {:command, action, params, opts})

      :async ->
        GenServer.cast(server, {:command_async, action, params, opts})
        :ok
    end
  end

  @spec subscribe(GenServer.server(), pid()) :: :ok | {:error, Error.t()}
  def subscribe(server, subscriber \\ self()) when is_pid(subscriber) do
    GenServer.call(server, {:subscribe, subscriber})
  end

  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(server, subscriber \\ self()) when is_pid(subscriber) do
    GenServer.call(server, {:unsubscribe, subscriber})
  end

  @spec state(GenServer.server()) :: state()
  def state(server), do: GenServer.call(server, :state)

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, default_session_id())
    signal_bus = Keyword.get(opts, :signal_bus, SignalBus)

    state = %__MODULE__{session_id: session_id, signal_bus: signal_bus}

    auto_load_path = Keyword.get(opts, :path)

    state =
      if is_binary(auto_load_path) do
        execute_boot_load(state, auto_load_path, opts)
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    _ =
      emit_signal(state, :session_closed, %{
        history_size: length(state.history),
        revision: current_revision(state)
      })

    :ok
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    case SignalBus.subscribe(state.signal_bus, state.session_id, pid: subscriber) do
      :ok -> {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, subscriber)}}
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    :ok = SignalBus.unsubscribe(state.signal_bus, state.session_id, pid: subscriber)
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, subscriber)}}
  end

  def handle_call(:state, _from, state), do: {:reply, state, state}

  def handle_call({:command, action, params, opts}, _from, state) do
    {result, state} = execute_command(state, action, params, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:command_async, action, params, opts}, state) do
    {_result, state} = execute_command(state, action, params, opts)
    {:noreply, state}
  end

  defp execute_boot_load(state, path, opts) do
    {result, updated} = execute_command(state, :load, %{path: path}, opts)

    case result.status do
      :ok -> updated
      :error -> updated
    end
  end

  defp execute_command(state, action, params, opts) do
    params = normalize_map(params)
    opts = normalize_map(opts)
    params = inject_command_defaults(state, action, params)

    with :ok <- guard_action(state, action) do
      previous_state = state
      state = lock_if_needed(state, action)

      context = %{
        session_id: state.session_id,
        path: Map.get(params, :path),
        document: Map.get(params, :document, state.document),
        options: Map.get(opts, :context_options, %{}),
        correlation_id: Map.get(opts, :correlation_id),
        idempotency_key: Map.get(opts, :idempotency_key),
        metadata: %{action: action}
      }

      result = Action.execute(action_module(action), params, context)

      case result do
        %Result{status: :ok, value: value} = ok_result ->
          next_state =
            state
            |> apply_success(action, value, ok_result.metadata)
            |> unlock_if_needed(action)

          {ok_result, next_state}

        %Result{status: :error, error: error} = error_result ->
          if action == :render do
            fallback_value = %{
              preview: choose_fallback_preview(state, error),
              revision: current_revision(state),
              document: state.document
            }

            recovered_state =
              state
              |> unlock_if_needed(action)
              |> apply_failure(action, error, error_result.metadata, true)

            next_state =
              apply_success(
                recovered_state,
                :render,
                fallback_value,
                Map.put(error_result.metadata, :fallback, true)
              )

            {Result.ok(fallback_value, Map.put(error_result.metadata, :fallback, true)),
             next_state}
          else
            rollback? = Map.get(opts, :optimistic, true)

            recovered_state =
              if rollback? and action in [:update_frontmatter, :update_body] do
                previous_state
              else
                state
              end

            next_state =
              recovered_state
              |> unlock_if_needed(action)
              |> apply_failure(action, error, error_result.metadata, rollback?)

            {error_result, next_state}
          end
      end
    else
      {:error, %Error{} = error} ->
        result = Result.error(error, %{action: action, session_id: state.session_id})
        {result, state}
    end
  end

  defp guard_action(state, action) do
    cond do
      action == :save and locked?(state, :save) ->
        {:error, Error.new(:busy, "save already in progress", %{action: action})}

      action == :save and locked?(state, :render) ->
        {:error, Error.new(:busy, "render in progress; save deferred", %{action: action})}

      action == :render and locked?(state, :render) ->
        {:error, Error.new(:busy, "render already in progress", %{action: action})}

      action in [:update_frontmatter, :update_body] and locked?(state, :save) ->
        {:error, Error.new(:busy, "save lock prevents update", %{action: action})}

      true ->
        :ok
    end
  end

  defp apply_success(state, action, value, metadata) do
    previous_fallback = state.render_fallback_active

    state =
      case action do
        :load ->
          %{
            state
            | document: Map.get(value, :document),
              disk_snapshot: Map.get(value, :disk_snapshot),
              preview: nil,
              last_good_preview: nil,
              render_fallback_active: false
          }

        :save ->
          %{
            state
            | document: Map.get(value, :document, state.document),
              disk_snapshot: Map.get(value, :disk_snapshot, state.disk_snapshot)
          }

        :update_frontmatter ->
          %{state | document: Map.get(value, :document, state.document)}

        :update_body ->
          %{state | document: Map.get(value, :document, state.document)}

        :render ->
          apply_render_state(state, Map.get(value, :preview))
      end

    signal_type = signal_type_for_success(action)

    _ =
      emit_signal(
        state,
        signal_type,
        %{
          action: action,
          revision: current_revision(state),
          payload: compact_payload(value),
          metadata: metadata
        }
      )

    if action == :render and previous_fallback and not state.render_fallback_active do
      _ =
        emit_signal(state, :updated, %{
          action: :render_recovered,
          revision: current_revision(state),
          metadata: metadata
        })
    end

    entry = %{
      action: action,
      revision: current_revision(state),
      timestamp: DateTime.utc_now(),
      correlation_id: Map.get(metadata, :correlation_id)
    }

    %{state | history: [entry | state.history]}
  end

  defp apply_failure(state, action, %Error{} = error, metadata, rollback?) do
    _ =
      emit_signal(state, :failed, %{
        action: action,
        revision: current_revision(state),
        error: Error.to_map(error),
        rollback: rollback?,
        metadata: metadata
      })

    state
  end

  defp signal_type_for_success(:load), do: :loaded
  defp signal_type_for_success(:save), do: :saved
  defp signal_type_for_success(:render), do: :rendered
  defp signal_type_for_success(_), do: :updated

  defp emit_signal(state, type, data) do
    SignalBus.broadcast(
      state.signal_bus,
      type,
      state.session_id,
      data,
      correlation_id: correlation_id_from(data),
      source: :agent
    )
  end

  defp correlation_id_from(%{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, :correlation_id)

  defp correlation_id_from(_), do: nil

  defp action_module(:load), do: Jido.Document.Actions.Load
  defp action_module(:save), do: Jido.Document.Actions.Save
  defp action_module(:update_frontmatter), do: Jido.Document.Actions.UpdateFrontmatter
  defp action_module(:update_body), do: Jido.Document.Actions.UpdateBody
  defp action_module(:render), do: Jido.Document.Actions.Render

  defp lock_if_needed(state, action) when action in [:save, :render],
    do: %{state | locks: MapSet.put(state.locks, action)}

  defp lock_if_needed(state, _action), do: state

  defp unlock_if_needed(state, action) when action in [:save, :render],
    do: %{state | locks: MapSet.delete(state.locks, action)}

  defp unlock_if_needed(state, _action), do: state

  defp locked?(state, lock), do: MapSet.member?(state.locks, lock)

  defp compact_payload(%{} = value) do
    value
    |> Map.drop([:document, :preview])
    |> maybe_put(:document_revision, value[:document] && value.document.revision)
    |> maybe_put(
      :preview_summary,
      value[:preview] && %{toc_size: length(value.preview.toc || [])}
    )
  end

  defp compact_payload(_), do: %{}

  defp current_revision(%__MODULE__{document: %Document{revision: revision}}), do: revision
  defp current_revision(_), do: nil

  defp choose_fallback_preview(state, error) do
    fallback_diag = %{
      severity: :error,
      message: "render fallback active: #{error.message}",
      location: nil,
      hint: "Fix render diagnostics and retry render",
      code: :render_failure
    }

    case state.last_good_preview do
      %{} = preview ->
        diagnostics = (preview[:diagnostics] || []) ++ [fallback_diag]

        preview
        |> Map.put(:diagnostics, diagnostics)
        |> Map.put(:adapter, :fallback)
        |> Map.update(
          :metadata,
          %{fallback: true, source: :last_good},
          &Map.merge(&1, %{fallback: true, source: :last_good})
        )

      _ ->
        Jido.Document.Renderer.fallback_preview(
          (state.document && state.document.body) || "",
          error
        )
    end
  end

  defp apply_render_state(state, nil), do: state

  defp apply_render_state(state, preview) when is_map(preview) do
    fallback? =
      Map.get(preview, :adapter) == :fallback or get_in(preview, [:metadata, :fallback]) == true

    if fallback? do
      %{state | preview: preview, render_fallback_active: true}
    else
      %{state | preview: preview, last_good_preview: preview, render_fallback_active: false}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_map(%{} = map), do: map
  defp normalize_map(list) when is_list(list), do: Map.new(list)
  defp normalize_map(_), do: %{}

  defp inject_command_defaults(state, :save, params) do
    if Map.has_key?(params, :baseline) do
      params
    else
      Map.put(params, :baseline, state.disk_snapshot)
    end
  end

  defp inject_command_defaults(_state, _action, params), do: params

  defp default_session_id do
    "session-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
