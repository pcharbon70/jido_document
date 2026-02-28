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
  alias Jido.Document.{Checkpoint, Document, Error, History, Persistence, SignalBus}

  @supported_actions [:load, :save, :update_frontmatter, :update_body, :render, :undo, :redo]

  @type action_name ::
          :load | :save | :update_frontmatter | :update_body | :render | :undo | :redo

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
          history_model: History.t(),
          pending_checkpoint: Checkpoint.payload() | nil,
          checkpoint_opts: keyword(),
          autosave_interval_ms: non_neg_integer() | nil,
          checkpoint_on_edit: boolean(),
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
            history_model: %History{},
            pending_checkpoint: nil,
            checkpoint_opts: [],
            autosave_interval_ms: nil,
            checkpoint_on_edit: true,
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

  @spec recovery_status(GenServer.server()) :: Checkpoint.payload() | nil
  def recovery_status(server), do: GenServer.call(server, :recovery_status)

  @spec recover(GenServer.server(), keyword()) :: Result.t()
  def recover(server, opts \\ []), do: GenServer.call(server, {:recover, opts})

  @spec discard_recovery(GenServer.server()) :: Result.t()
  def discard_recovery(server), do: GenServer.call(server, :discard_recovery)

  @spec list_recovery_candidates(keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_recovery_candidates(opts \\ []) do
    checkpoint_opts = checkpoint_opts_from(opts)

    with {:ok, paths} <- Checkpoint.list_orphans(checkpoint_opts) do
      {:ok,
       Enum.map(paths, fn path ->
         session_id = Path.basename(path, ".checkpoint")
         %{session_id: session_id, checkpoint_path: path}
       end)}
    end
  end

  @impl true
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, default_session_id())
    signal_bus = Keyword.get(opts, :signal_bus, SignalBus)
    history_limit = Keyword.get(opts, :history_limit, 100)
    checkpoint_opts = checkpoint_opts_from(opts)
    autosave_interval_ms = normalize_autosave_interval(Keyword.get(opts, :autosave_interval_ms))
    checkpoint_on_edit = Keyword.get(opts, :checkpoint_on_edit, true)

    state = %__MODULE__{
      session_id: session_id,
      signal_bus: signal_bus,
      history_model: History.new(limit: history_limit),
      checkpoint_opts: checkpoint_opts,
      autosave_interval_ms: autosave_interval_ms,
      checkpoint_on_edit: checkpoint_on_edit
    }

    state = load_pending_checkpoint(state)

    if autosave_interval_ms != nil do
      schedule_autosave(autosave_interval_ms)
    end

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
  def handle_call(:recovery_status, _from, state), do: {:reply, state.pending_checkpoint, state}

  def handle_call({:recover, opts}, _from, state) do
    {result, state} = recover_from_checkpoint(state, normalize_map(opts))
    {:reply, result, state}
  end

  def handle_call(:discard_recovery, _from, state) do
    {result, state} = discard_pending_checkpoint(state)
    {:reply, result, state}
  end

  def handle_call({:command, action, params, opts}, _from, state) do
    {result, state} = execute_command(state, action, params, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:command_async, action, params, opts}, state) do
    {_result, state} = execute_command(state, action, params, opts)
    {:noreply, state}
  end

  @impl true
  def handle_info(:autosave_checkpoint, state) do
    state = maybe_write_checkpoint(state, :timer, %{})

    if state.autosave_interval_ms != nil do
      schedule_autosave(state.autosave_interval_ms)
    end

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

      {result, next_state} =
        if action in [:undo, :redo] do
          execute_history_command(state, action, opts)
        else
          execute_action_command(state, previous_state, action, params, opts)
        end

      {result, unlock_if_needed(next_state, action)}
    else
      {:error, %Error{} = error} ->
        result = Result.error(error, %{action: action, session_id: state.session_id})
        {result, state}
    end
  end

  defp execute_action_command(state, previous_state, action, params, opts) do
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
        next_state = apply_success(state, action, value, ok_result.metadata)
        {ok_result, next_state}

      %Result{status: :error, error: error} = error_result ->
        if action == :render do
          fallback_value = %{
            preview: choose_fallback_preview(state, error),
            revision: current_revision(state),
            document: state.document
          }

          recovered_state =
            apply_failure(state, action, error, error_result.metadata, true)

          next_state =
            apply_success(
              recovered_state,
              :render,
              fallback_value,
              Map.put(error_result.metadata, :fallback, true)
            )

          {Result.ok(fallback_value, Map.put(error_result.metadata, :fallback, true)), next_state}
        else
          rollback? = Map.get(opts, :optimistic, true)

          recovered_state =
            if rollback? and action in [:update_frontmatter, :update_body] do
              previous_state
            else
              state
            end

          next_state =
            apply_failure(recovered_state, action, error, error_result.metadata, rollback?)

          {error_result, next_state}
        end
    end
  end

  defp execute_history_command(state, action, opts) do
    started = System.monotonic_time(:microsecond)
    correlation_id = Map.get(opts, :correlation_id, default_correlation_id())
    metadata = history_command_metadata(action, correlation_id, opts)

    cond do
      state.document == nil ->
        error =
          Error.new(:invalid_params, "#{action} requires a loaded document", %{action: action})

        metadata = finish_history_metadata(metadata, started)
        {Result.error(error, metadata), apply_failure(state, action, error, metadata, false)}

      true ->
        execute_history_transition(state, action, metadata, started)
    end
  end

  defp execute_history_transition(state, action, metadata, started) do
    result =
      case action do
        :undo -> History.undo(state.history_model, state.document)
        :redo -> History.redo(state.history_model, state.document)
      end

    metadata = finish_history_metadata(metadata, started)

    case result do
      {:ok, document, history_model} ->
        value = %{
          document: document,
          history_model: history_model,
          history: History.state(history_model),
          revision: document.revision
        }

        ok_result = Result.ok(value, metadata)
        next_state = apply_success(state, action, value, metadata)
        {ok_result, next_state}

      {:error, :empty} ->
        error =
          Error.new(:conflict, "#{action} unavailable", %{
            action: action,
            history: History.state(state.history_model)
          })

        error_result = Result.error(error, metadata)
        next_state = apply_failure(state, action, error, metadata, false)
        {error_result, next_state}
    end
  end

  defp history_command_metadata(action, correlation_id, opts) do
    %{
      action: action,
      idempotency: :conditionally_idempotent,
      correlation_id: correlation_id
    }
    |> maybe_put(:idempotency_key, Map.get(opts, :idempotency_key))
  end

  defp finish_history_metadata(metadata, started) do
    Map.put(metadata, :duration_us, System.monotonic_time(:microsecond) - started)
  end

  defp guard_action(state, action) do
    cond do
      action not in @supported_actions ->
        {:error, Error.new(:invalid_params, "unknown action", %{action: action})}

      action == :save and locked?(state, :save) ->
        {:error, Error.new(:busy, "save already in progress", %{action: action})}

      action == :save and locked?(state, :render) ->
        {:error, Error.new(:busy, "render in progress; save deferred", %{action: action})}

      action == :render and locked?(state, :render) ->
        {:error, Error.new(:busy, "render already in progress", %{action: action})}

      action in [:update_frontmatter, :update_body, :undo, :redo] and locked?(state, :save) ->
        {:error, Error.new(:busy, "save lock prevents update", %{action: action})}

      true ->
        :ok
    end
  end

  defp apply_success(state, action, value, metadata) do
    previous_fallback = state.render_fallback_active
    previous_history = history_state(state)

    state =
      case action do
        :load ->
          %{
            state
            | document: Map.get(value, :document),
              disk_snapshot: Map.get(value, :disk_snapshot),
              history_model: History.clear(state.history_model),
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
          apply_update_document_state(state, action, value, metadata)

        :update_body ->
          apply_update_document_state(state, action, value, metadata)

        :undo ->
          %{
            state
            | document: Map.get(value, :document, state.document),
              history_model: Map.get(value, :history_model, state.history_model)
          }

        :redo ->
          %{
            state
            | document: Map.get(value, :document, state.document),
              history_model: Map.get(value, :history_model, state.history_model)
          }

        :render ->
          apply_render_state(state, Map.get(value, :preview))
      end

    state = apply_checkpoint_policy(state, action, metadata)

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

    maybe_emit_history_state_signal(state, previous_history, action, metadata)

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
    |> Map.drop([:document, :preview, :history_model])
    |> maybe_put(:document_revision, value[:document] && value.document.revision)
    |> maybe_put(:history, value[:history])
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

  defp apply_update_document_state(state, action, value, metadata) do
    next_document = Map.get(value, :document, state.document)
    changed? = Map.get(value, :changed?, revision_changed?(state.document, next_document))

    history_model =
      if changed? do
        History.record(
          state.history_model,
          state.document,
          action,
          %{correlation_id: Map.get(metadata, :correlation_id)}
        )
      else
        state.history_model
      end

    %{state | document: next_document, history_model: history_model}
  end

  defp maybe_emit_history_state_signal(state, previous_history_state, action, metadata) do
    current_history_state = history_state(state)

    if current_history_state != previous_history_state do
      _ =
        emit_signal(state, :updated, %{
          action: :history_state,
          revision: current_revision(state),
          payload: Map.put(current_history_state, :trigger, action),
          metadata: metadata
        })
    end

    :ok
  end

  defp history_state(state), do: History.state(state.history_model)

  defp revision_changed?(%Document{revision: old_revision}, %Document{revision: new_revision}),
    do: old_revision != new_revision

  defp revision_changed?(_before, _after), do: true

  defp apply_checkpoint_policy(state, :save, _metadata) do
    case Checkpoint.discard(state.session_id, state.checkpoint_opts) do
      :ok ->
        %{state | pending_checkpoint: nil}

      {:error, %Error{} = error} ->
        _ =
          emit_signal(state, :failed, %{
            action: :checkpoint_discard,
            revision: current_revision(state),
            error: Error.to_map(error),
            rollback: false,
            metadata: %{}
          })

        state
    end
  end

  defp apply_checkpoint_policy(state, action, metadata)
       when action in [:update_frontmatter, :update_body, :undo, :redo] do
    maybe_write_checkpoint(state, :edit, metadata)
  end

  defp apply_checkpoint_policy(state, _action, _metadata), do: state

  defp maybe_write_checkpoint(state, reason, metadata) do
    write? =
      case reason do
        :edit -> state.checkpoint_on_edit
        _ -> true
      end

    if write? and checkpoint_writable?(state) do
      case Checkpoint.write(
             state.session_id,
             state.document,
             state.disk_snapshot,
             state.checkpoint_opts
           ) do
        {:ok, _path} ->
          case Checkpoint.load(state.session_id, state.checkpoint_opts) do
            {:ok, payload} ->
              %{state | pending_checkpoint: payload}

            _ ->
              state
          end

        {:error, %Error{} = error} ->
          _ =
            emit_signal(state, :failed, %{
              action: :checkpoint_write,
              revision: current_revision(state),
              error: Error.to_map(error),
              rollback: false,
              metadata: metadata
            })

          state
      end
    else
      state
    end
  end

  defp checkpoint_writable?(%__MODULE__{document: %Document{dirty: true}}), do: true
  defp checkpoint_writable?(_state), do: false

  defp load_pending_checkpoint(state) do
    case Checkpoint.load(state.session_id, state.checkpoint_opts) do
      {:ok, payload} ->
        _ =
          emit_signal(state, :updated, %{
            action: :recovery_available,
            revision: current_revision(state),
            payload: recovery_summary(payload)
          })

        %{state | pending_checkpoint: payload}

      {:error, :not_found} ->
        state

      {:error, %Error{} = error} ->
        _ =
          emit_signal(state, :failed, %{
            action: :recovery_load,
            revision: current_revision(state),
            error: Error.to_map(error),
            rollback: false,
            metadata: %{}
          })

        state
    end
  end

  defp recover_from_checkpoint(state, opts) do
    started = System.monotonic_time(:microsecond)
    metadata = op_metadata(:recover, opts)

    with {:ok, payload, state} <- fetch_pending_checkpoint(state),
         :ok <- ensure_recovery_safe(payload, Map.get(opts, :force, false)),
         :ok <- Checkpoint.discard(state.session_id, state.checkpoint_opts) do
      recovered_state = %{
        state
        | document: payload.document,
          disk_snapshot: payload.disk_snapshot,
          pending_checkpoint: nil,
          history_model: History.clear(state.history_model),
          preview: nil,
          last_good_preview: nil,
          render_fallback_active: false
      }

      metadata = finish_op_metadata(metadata, started)

      _ =
        emit_signal(recovered_state, :updated, %{
          action: :recovered,
          revision: current_revision(recovered_state),
          payload: Map.put(recovery_summary(payload), :force, Map.get(opts, :force, false)),
          metadata: metadata
        })

      entry = %{
        action: :load,
        revision: current_revision(recovered_state),
        timestamp: DateTime.utc_now(),
        correlation_id: Map.get(metadata, :correlation_id)
      }

      result =
        Result.ok(
          %{
            document: recovered_state.document,
            recovered: true,
            history: History.state(recovered_state.history_model)
          },
          metadata
        )

      {result, %{recovered_state | history: [entry | recovered_state.history]}}
    else
      {:error, %Error{} = error} ->
        metadata = finish_op_metadata(metadata, started)
        result = Result.error(error, metadata)
        {result, apply_failure(state, :load, error, metadata, false)}
    end
  end

  defp discard_pending_checkpoint(state) do
    started = System.monotonic_time(:microsecond)
    metadata = op_metadata(:discard_recovery, %{})

    case Checkpoint.discard(state.session_id, state.checkpoint_opts) do
      :ok ->
        metadata = finish_op_metadata(metadata, started)

        _ =
          emit_signal(state, :updated, %{
            action: :recovery_discarded,
            revision: current_revision(state),
            payload: %{session_id: state.session_id},
            metadata: metadata
          })

        {Result.ok(%{discarded: true}, metadata), %{state | pending_checkpoint: nil}}

      {:error, %Error{} = error} ->
        metadata = finish_op_metadata(metadata, started)
        result = Result.error(error, metadata)
        {result, apply_failure(state, :load, error, metadata, false)}
    end
  end

  defp fetch_pending_checkpoint(%__MODULE__{pending_checkpoint: %{} = payload} = state) do
    {:ok, payload, state}
  end

  defp fetch_pending_checkpoint(state) do
    case Checkpoint.load(state.session_id, state.checkpoint_opts) do
      {:ok, payload} ->
        {:ok, payload, %{state | pending_checkpoint: payload}}

      {:error, :not_found} ->
        {:error,
         Error.new(:not_found, "no checkpoint available", %{session_id: state.session_id})}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp ensure_recovery_safe(payload, true), do: ensure_payload_shape(payload)

  defp ensure_recovery_safe(payload, false) do
    with :ok <- ensure_payload_shape(payload),
         :ok <- ensure_recovery_not_diverged(payload) do
      :ok
    end
  end

  defp ensure_payload_shape(%{document: %Document{}}), do: :ok

  defp ensure_payload_shape(payload) do
    {:error, Error.new(:validation_failed, "checkpoint payload is invalid", %{payload: payload})}
  end

  defp ensure_recovery_not_diverged(%{document: %Document{path: path}, disk_snapshot: baseline})
       when is_binary(path) and is_map(baseline) do
    case Persistence.detect_divergence(path, baseline) do
      :ok ->
        :ok

      {:error, %Error{code: :conflict} = error} ->
        {:error,
         Error.merge_details(error, %{
           remediation: [:force_recover, :discard, :reload]
         })}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp ensure_recovery_not_diverged(_payload), do: :ok

  defp recovery_summary(payload) do
    %{
      session_id: payload.session_id,
      captured_at_ms: payload.captured_at_ms,
      path: payload.document.path,
      revision: payload.document.revision
    }
  end

  defp schedule_autosave(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :autosave_checkpoint, interval_ms)
  end

  defp schedule_autosave(_interval_ms), do: :ok

  defp normalize_autosave_interval(value) when is_integer(value) and value > 0, do: value
  defp normalize_autosave_interval(_value), do: nil

  defp checkpoint_opts_from(opts) when is_list(opts) do
    case Keyword.get(opts, :checkpoint_dir) do
      dir when is_binary(dir) and dir != "" -> [dir: dir]
      _ -> []
    end
  end

  defp checkpoint_opts_from(%{} = opts) do
    case Map.get(opts, :checkpoint_dir) do
      dir when is_binary(dir) and dir != "" -> [dir: dir]
      _ -> []
    end
  end

  defp checkpoint_opts_from(_opts), do: []

  defp op_metadata(action, opts) do
    %{
      action: action,
      correlation_id: Map.get(opts, :correlation_id, default_correlation_id()),
      idempotency: :non_idempotent
    }
    |> maybe_put(:idempotency_key, Map.get(opts, :idempotency_key))
  end

  defp finish_op_metadata(metadata, started) do
    Map.put(metadata, :duration_us, System.monotonic_time(:microsecond) - started)
  end

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

  defp default_correlation_id do
    "jd-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp default_session_id do
    "session-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
