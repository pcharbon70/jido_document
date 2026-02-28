defmodule JidoDocs.Adapters.LiveView do
  @moduledoc """
  Thin LiveView-facing adapter around session registry, commands, and signals.
  """

  alias JidoDocs.Action.Result
  alias JidoDocs.Adapters.LiveViewForm
  alias JidoDocs.{Agent, Error, SessionRegistry, Signal, SignalBus}

  @type t :: %__MODULE__{
          registry: GenServer.server(),
          signal_bus: GenServer.server(),
          session_id: String.t(),
          session_pid: pid(),
          schema: module() | nil,
          assigns: map()
        }

  defstruct registry: SessionRegistry,
            signal_bus: SignalBus,
            session_id: nil,
            session_pid: nil,
            schema: nil,
            assigns: %{
              document: nil,
              preview: nil,
              revision: nil,
              dirty: false,
              save_state: :idle,
              saving: false,
              validation_errors: [],
              last_error: nil,
              lock_state: nil,
              frontmatter_form: %{fields: [], errors: %{}, hints: %{}}
            }

  @spec mount(map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def mount(params, opts \\ []) when is_map(params) do
    registry = Keyword.get(opts, :registry, SessionRegistry)
    signal_bus = Keyword.get(opts, :signal_bus, SignalBus)
    schema = Keyword.get(opts, :schema)

    with {:ok, session_info} <- ensure_session(registry, params),
         :ok <- SignalBus.subscribe(signal_bus, session_info.session_id, pid: self()) do
      adapter = %__MODULE__{
        registry: registry,
        signal_bus: signal_bus,
        session_id: session_info.session_id,
        session_pid: session_info.pid,
        schema: schema
      }

      {:ok, refresh_assigns(adapter)}
    end
  end

  @spec handle_event(t(), String.t() | atom(), map()) ::
          {:noreply, t()} | {:error, Error.t(), t()}
  def handle_event(adapter, event, params \\ %{})

  def handle_event(adapter, event, _params) when event in ["connect", :connect] do
    {:noreply, refresh_assigns(adapter, save_state: :connected)}
  end

  def handle_event(adapter, event, %{"changes" => changes})
      when event in ["frontmatter_change", :frontmatter_change] and is_map(changes) do
    proposed_frontmatter =
      adapter.assigns.document
      |> frontmatter_from_assigns()
      |> Map.merge(changes)

    {form, validation_errors} =
      LiveViewForm.validate_and_build(adapter.schema, proposed_frontmatter)

    next = put_form(adapter, form, validation_errors)

    if validation_errors == [] do
      run_command(next, :update_frontmatter, %{changes: changes})
    else
      {:noreply,
       with_error(
         next,
         Error.new(:validation_failed, "frontmatter validation failed", %{
           errors: validation_errors
         })
       )}
    end
  end

  def handle_event(adapter, event, %{"body" => body})
      when event in ["body_change", :body_change] and is_binary(body) do
    run_command(adapter, :update_body, %{body: body})
  end

  def handle_event(adapter, event, params) when event in ["save", :save] and is_map(params) do
    run_command(set_save_state(adapter, :saving), :save, normalize_save_params(params))
  end

  def handle_event(adapter, event, _params) when event in ["render", :render] do
    run_command(adapter, :render, %{})
  end

  def handle_event(adapter, _event, _params) do
    {:error, Error.new(:invalid_params, "unsupported liveview event", %{}), adapter}
  end

  @spec handle_info(t(), term()) :: {:noreply, t()}
  def handle_info(%__MODULE__{} = adapter, {:jido_docs_signal, %Signal{} = signal}) do
    {:noreply, handle_signal(adapter, signal)}
  end

  def handle_info(%__MODULE__{} = adapter, _message), do: {:noreply, adapter}

  @spec handle_signal(t(), Signal.t()) :: t()
  def handle_signal(%__MODULE__{} = adapter, %Signal{session_id: session_id} = signal)
      when session_id == adapter.session_id do
    adapter =
      adapter
      |> refresh_assigns()
      |> Map.update!(:assigns, &Map.put(&1, :last_signal, signal.type))

    case signal.type do
      :saved ->
        set_save_state(adapter, :saved)

      :failed ->
        error = signal.data[:error] || %{message: "action failed"}
        with_error(set_save_state(adapter, :error), Error.new(:internal, "action failed", error))

      :updated ->
        case get_in(signal.data, [:payload, :action]) do
          :takeover -> put_lock_state(adapter, get_in(signal.data, [:payload]))
          :released -> put_lock_state(adapter, get_in(signal.data, [:payload]))
          _ -> adapter
        end

      _ ->
        adapter
    end
  end

  def handle_signal(adapter, _signal), do: adapter

  defp ensure_session(registry, params) do
    cond do
      is_binary(params["session_id"]) ->
        SessionRegistry.ensure_session(registry, params["session_id"])

      is_binary(params[:session_id]) ->
        SessionRegistry.ensure_session(registry, params[:session_id])

      is_binary(params["path"]) ->
        SessionRegistry.ensure_session_by_path(registry, params["path"])

      is_binary(params[:path]) ->
        SessionRegistry.ensure_session_by_path(registry, params[:path])

      true ->
        {:error,
         Error.new(:invalid_params, "mount requires session_id or path", %{params: params})}
    end
  end

  defp run_command(adapter, action, params) do
    SessionRegistry.touch(adapter.registry, adapter.session_id)

    case Agent.command(adapter.session_pid, action, params) do
      %Result{status: :ok} ->
        updated =
          adapter
          |> refresh_assigns()
          |> clear_error()
          |> set_save_state(post_action_state(action))

        {:noreply, updated}

      %Result{status: :error, error: %Error{} = error} ->
        state = if action == :save, do: :error, else: adapter.assigns.save_state
        {:error, error, with_error(set_save_state(refresh_assigns(adapter), state), error)}
    end
  end

  defp refresh_assigns(%__MODULE__{} = adapter, overrides \\ []) do
    state = Agent.state(adapter.session_pid)
    document = state.document
    form = LiveViewForm.build(adapter.schema, (document && document.frontmatter) || %{})

    assigns =
      adapter.assigns
      |> Map.merge(%{
        document: document,
        preview: state.preview,
        revision: document && document.revision,
        dirty: (document && document.dirty) || false,
        saving: false,
        frontmatter_form: form
      })
      |> Map.merge(Map.new(overrides))
      |> Map.new()

    %{adapter | assigns: assigns}
  end

  defp put_form(adapter, form, validation_errors) do
    %{
      adapter
      | assigns:
          Map.merge(adapter.assigns, %{
            frontmatter_form: form,
            validation_errors: validation_errors
          })
    }
  end

  defp with_error(adapter, %Error{} = error),
    do: %{adapter | assigns: Map.put(adapter.assigns, :last_error, error)}

  defp clear_error(adapter), do: %{adapter | assigns: Map.put(adapter.assigns, :last_error, nil)}

  defp put_lock_state(adapter, payload),
    do: %{adapter | assigns: Map.put(adapter.assigns, :lock_state, payload)}

  defp set_save_state(adapter, state) do
    %{
      adapter
      | assigns: Map.merge(adapter.assigns, %{save_state: state, saving: state == :saving})
    }
  end

  defp frontmatter_from_assigns(nil), do: %{}
  defp frontmatter_from_assigns(document), do: document.frontmatter || %{}

  defp post_action_state(:save), do: :saved
  defp post_action_state(_), do: :idle

  defp normalize_save_params(params) do
    cond do
      is_binary(params[:path]) -> %{path: params[:path]}
      is_binary(params["path"]) -> %{path: params["path"]}
      true -> params
    end
  end
end
