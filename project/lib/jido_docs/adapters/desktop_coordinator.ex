defmodule JidoDocs.Adapters.DesktopCoordinator do
  @moduledoc """
  Coordinates desktop windows over shared or isolated session processes.
  """

  use GenServer

  alias JidoDocs.Action.Result
  alias JidoDocs.Adapters.DesktopIPC
  alias JidoDocs.{Agent, Error, SessionRegistry, Signal, SignalBus}

  @type window_mode :: :shared | :isolated

  @type window_info :: %{
          window_id: String.t(),
          owner_id: String.t(),
          mode: window_mode(),
          session_id: String.t(),
          session_pid: pid(),
          lock_token: String.t() | nil,
          connected: boolean(),
          outbox: [map()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec register_window(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def register_window(server \\ __MODULE__, window_id, params, opts \\ []) do
    GenServer.call(server, {:register_window, window_id, params, opts})
  end

  @spec unregister_window(GenServer.server(), String.t()) :: :ok
  def unregister_window(server \\ __MODULE__, window_id) do
    GenServer.call(server, {:unregister_window, window_id})
  end

  @spec disconnect_window(GenServer.server(), String.t()) :: :ok | {:error, Error.t()}
  def disconnect_window(server \\ __MODULE__, window_id) do
    GenServer.call(server, {:disconnect_window, window_id})
  end

  @spec reconnect_window(GenServer.server(), String.t(), keyword()) ::
          {:ok, %{window: map(), replay: [map()]}} | {:error, Error.t()}
  def reconnect_window(server \\ __MODULE__, window_id, opts \\ []) do
    GenServer.call(server, {:reconnect_window, window_id, opts})
  end

  @spec handle_ipc_request(GenServer.server(), String.t(), map()) ::
          {:ok, map()} | {:error, map()}
  def handle_ipc_request(server \\ __MODULE__, window_id, payload) do
    GenServer.call(server, {:handle_ipc_request, window_id, payload})
  end

  @spec drain_outbox(GenServer.server(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def drain_outbox(server \\ __MODULE__, window_id) do
    GenServer.call(server, {:drain_outbox, window_id})
  end

  @spec list_windows(GenServer.server(), String.t() | nil) :: [map()]
  def list_windows(server \\ __MODULE__, session_id \\ nil) do
    GenServer.call(server, {:list_windows, session_id})
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       registry: Keyword.get(opts, :registry, SessionRegistry),
       signal_bus: Keyword.get(opts, :signal_bus, SignalBus),
       max_replay_events: Keyword.get(opts, :max_replay_events, 64),
       windows: %{},
       session_windows: %{},
       replay: %{},
       subscribed_sessions: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:register_window, window_id, params, opts}, _from, state) do
    with :ok <- validate_window_id(window_id),
         {:ok, mode} <- parse_mode(params),
         {:ok, session_info} <- ensure_session_for_window(state, window_id, mode, params),
         {:ok, state} <- ensure_session_subscription(state, session_info.session_id) do
      owner_id = Keyword.get(opts, :owner_id, "desktop:" <> window_id)

      info = %{
        window_id: window_id,
        owner_id: owner_id,
        mode: mode,
        session_id: session_info.session_id,
        session_pid: session_info.pid,
        lock_token: nil,
        connected: true,
        outbox: []
      }

      state =
        state
        |> put_window(info)
        |> index_window(info.session_id, window_id)

      {:reply, {:ok, window_descriptor(info)}, state}
    else
      {:error, %Error{} = error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:unregister_window, window_id}, _from, state) do
    {:reply, :ok, remove_window(state, window_id)}
  end

  def handle_call({:disconnect_window, window_id}, _from, state) do
    case Map.get(state.windows, window_id) do
      nil ->
        {:reply, {:error, Error.new(:not_found, "window not found", %{window_id: window_id})},
         state}

      info ->
        updated = %{info | connected: false}
        {:reply, :ok, put_window(state, updated)}
    end
  end

  def handle_call({:reconnect_window, window_id, opts}, _from, state) do
    with {:ok, info} <- fetch_window(state, window_id),
         {:ok, session_info} <- SessionRegistry.ensure_session(state.registry, info.session_id),
         {:ok, state} <- ensure_session_subscription(state, info.session_id) do
      replay = replay_events_for(state, info.session_id, Keyword.get(opts, :since_revision))

      updated = %{info | connected: true, session_pid: session_info.pid}
      state = put_window(state, updated)

      {:reply, {:ok, %{window: window_descriptor(updated), replay: replay}}, state}
    else
      {:error, %Error{} = error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:handle_ipc_request, window_id, payload}, _from, state) do
    with {:ok, window} <- fetch_window(state, window_id),
         {:ok, request} <- DesktopIPC.decode_request(payload),
         :ok <- ensure_window_session_match(window, request),
         {:ok, state, _window, response} <- dispatch_request(state, window, request) do
      {:reply, {:ok, response}, state}
    else
      {:error, %Error{} = error} ->
        response = DesktopIPC.encode_error_response(nil, error)
        {:reply, {:error, response}, state}

      {:error, %Error{} = error, %{} = request} ->
        response = DesktopIPC.encode_error_response(request, error)
        {:reply, {:error, response}, state}
    end
  end

  def handle_call({:drain_outbox, window_id}, _from, state) do
    with {:ok, info} <- fetch_window(state, window_id) do
      state = put_window(state, %{info | outbox: []})
      {:reply, {:ok, info.outbox}, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:list_windows, session_id}, _from, state) do
    windows =
      state.windows
      |> Map.values()
      |> Enum.filter(fn info -> is_nil(session_id) or info.session_id == session_id end)
      |> Enum.map(&window_descriptor/1)
      |> Enum.sort_by(& &1.window_id)

    {:reply, windows, state}
  end

  @impl true
  def handle_info({:jido_docs_signal, %Signal{} = signal}, state) do
    event = DesktopIPC.encode_signal_event(signal, source: :desktop_coordinator)

    window_ids =
      Map.get(state.session_windows, signal.session_id, MapSet.new()) |> MapSet.to_list()

    state =
      state
      |> append_replay(signal.session_id, event)
      |> append_outbox(window_ids, event)
      |> apply_lock_state(signal)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp dispatch_request(state, window, request) do
    with :ok <- ensure_connected(window),
         {:ok, state, window} <- ensure_write_lock(state, window, request),
         {:ok, response_payload} <- run_window_action(state, window, request) do
      window =
        window
        |> sync_lock_token(request.action, response_payload)
        |> clear_lock_on_release(request.action)

      state = put_window(state, window)
      response = DesktopIPC.encode_ok_response(request, response_payload)
      {:ok, state, window, response}
    else
      {:error, %Error{} = error} ->
        maybe_prompt_conflict(state, window, request, error)
    end
  end

  defp run_window_action(state, window, request) do
    action = request.action
    params = normalize_action_params(action, request.params, request.path)

    case action do
      :force_takeover ->
        with {:ok, payload} <-
               SessionRegistry.force_takeover(
                 state.registry,
                 window.session_id,
                 window.owner_id,
                 reason: params[:reason]
               ) do
          {:ok, %{lock: payload, session_id: window.session_id}}
        end

      _ ->
        case Agent.command(window.session_pid, action, params) do
          %Result{status: :ok, value: value} ->
            {:ok, normalize_ok_payload(value, action)}

          %Result{status: :error, error: %Error{} = error} ->
            {:error, error}
        end
    end
  end

  defp ensure_write_lock(state, window, %{action: action} = request)
       when action in [:update_frontmatter, :update_body, :save] do
    if window.lock_token do
      if is_binary(request.lock_token) and request.lock_token != window.lock_token do
        {:error,
         Error.new(:conflict, "stale lock token", %{
           window_id: window.window_id,
           session_id: window.session_id
         })}
      else
        {:ok, state, window}
      end
    else
      case SessionRegistry.acquire_lock(state.registry, window.session_id, window.owner_id,
             expected_token: request.lock_token
           ) do
        {:ok, lock} ->
          updated = %{window | lock_token: lock.lock_token}
          {:ok, put_window(state, updated), updated}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  defp ensure_write_lock(state, window, _request), do: {:ok, state, window}

  defp clear_lock_on_release(window, :force_takeover), do: window
  defp clear_lock_on_release(window, _), do: window

  defp sync_lock_token(window, :force_takeover, payload) do
    case get_in(payload, ["lock", "lock_token"]) do
      token when is_binary(token) -> %{window | lock_token: token}
      _ -> window
    end
  end

  defp sync_lock_token(window, _action, _payload), do: window

  defp maybe_prompt_conflict(state, window, request, %Error{code: :conflict} = error) do
    event =
      DesktopIPC.conflict_prompt_event(window.window_id, window.session_id, %{
        action: request.action,
        details: error.details
      })

    state = append_outbox(state, [window.window_id], event)
    {:ok, state, window, DesktopIPC.encode_error_response(request, error)}
  end

  defp maybe_prompt_conflict(_state, _window, request, %Error{} = error) do
    {:error, error, request}
  end

  defp ensure_connected(%{connected: true}), do: :ok

  defp ensure_connected(window) do
    {:error,
     Error.new(:subscription_error, "window disconnected", %{window_id: window.window_id})}
  end

  defp ensure_window_session_match(window, request) do
    cond do
      is_binary(request.session_id) and request.session_id != window.session_id ->
        {:error,
         Error.new(:conflict, "window/session mismatch", %{
           window_session_id: window.session_id,
           request_session_id: request.session_id
         })}

      true ->
        :ok
    end
  end

  defp ensure_session_for_window(state, _window_id, :shared, params) do
    if is_binary(get_param(params, :session_id)) do
      SessionRegistry.ensure_session(state.registry, get_param(params, :session_id))
    else
      SessionRegistry.ensure_session_by_path(state.registry, get_param(params, :path))
    end
  end

  defp ensure_session_for_window(state, window_id, :isolated, params) do
    if is_binary(get_param(params, :path)) do
      path = get_param(params, :path)
      base_id = SessionRegistry.session_id_for_path(path)
      isolated_id = base_id <> "-iso-" <> short_id(window_id)
      SessionRegistry.ensure_session(state.registry, isolated_id, path: path)
    else
      base = get_param(params, :session_id)
      isolated_id = base <> "-iso-" <> short_id(window_id)
      SessionRegistry.ensure_session(state.registry, isolated_id)
    end
  end

  defp ensure_session_subscription(state, session_id) do
    if MapSet.member?(state.subscribed_sessions, session_id) do
      {:ok, state}
    else
      case SignalBus.subscribe(state.signal_bus, session_id, pid: self()) do
        :ok ->
          {:ok, %{state | subscribed_sessions: MapSet.put(state.subscribed_sessions, session_id)}}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    end
  end

  defp parse_mode(params) do
    mode = get_param(params, :mode) || "shared"

    case mode do
      :shared -> {:ok, :shared}
      :isolated -> {:ok, :isolated}
      "shared" -> {:ok, :shared}
      "isolated" -> {:ok, :isolated}
      other -> {:error, Error.new(:invalid_params, "invalid mode", %{mode: other})}
    end
  end

  defp validate_window_id(window_id) when is_binary(window_id) and window_id != "", do: :ok

  defp validate_window_id(window_id) do
    {:error,
     Error.new(:invalid_params, "window_id must be non-empty string", %{window_id: window_id})}
  end

  defp fetch_window(state, window_id) do
    case Map.get(state.windows, window_id) do
      nil -> {:error, Error.new(:not_found, "window not found", %{window_id: window_id})}
      info -> {:ok, info}
    end
  end

  defp put_window(state, info) do
    %{state | windows: Map.put(state.windows, info.window_id, info)}
  end

  defp remove_window(state, window_id) do
    case Map.get(state.windows, window_id) do
      nil ->
        state

      info ->
        updated_session_windows =
          state.session_windows
          |> Map.update(info.session_id, MapSet.new(), &MapSet.delete(&1, window_id))
          |> Enum.reduce(%{}, fn {session_id, set}, acc ->
            if MapSet.size(set) == 0, do: acc, else: Map.put(acc, session_id, set)
          end)

        %{
          state
          | windows: Map.delete(state.windows, window_id),
            session_windows: updated_session_windows
        }
    end
  end

  defp index_window(state, session_id, window_id) do
    set = Map.get(state.session_windows, session_id, MapSet.new()) |> MapSet.put(window_id)
    %{state | session_windows: Map.put(state.session_windows, session_id, set)}
  end

  defp append_outbox(state, window_ids, event) do
    Enum.reduce(window_ids, state, fn window_id, acc ->
      case Map.get(acc.windows, window_id) do
        nil ->
          acc

        info ->
          updated = %{info | outbox: info.outbox ++ [event]}
          put_window(acc, updated)
      end
    end)
  end

  defp append_replay(state, session_id, event) do
    current = Map.get(state.replay, session_id, [])
    next = (current ++ [event]) |> Enum.take(-state.max_replay_events)
    %{state | replay: Map.put(state.replay, session_id, next)}
  end

  defp replay_events_for(state, session_id, nil) do
    Map.get(state.replay, session_id, [])
  end

  defp replay_events_for(state, session_id, since_revision) do
    Map.get(state.replay, session_id, [])
    |> Enum.filter(fn event ->
      revision = event["revision"]
      is_integer(revision) and revision > since_revision
    end)
  end

  defp normalize_action_params(:load, params, path) do
    path = get_param(params, :path) || path
    %{path: path}
  end

  defp normalize_action_params(:save, params, _path) do
    %{path: get_param(params, :path)}
  end

  defp normalize_action_params(:update_frontmatter, params, _path) do
    %{changes: get_param(params, :changes) || %{}}
  end

  defp normalize_action_params(:update_body, params, _path) do
    %{body: get_param(params, :body) || ""}
  end

  defp normalize_action_params(:render, _params, _path), do: %{}

  defp normalize_action_params(:force_takeover, params, _path),
    do: %{reason: get_param(params, :reason)}

  defp normalize_ok_payload(value, action) when is_map(value) do
    value
    |> Map.drop([:document, :preview])
    |> Map.put_new(:action, action)
    |> stringify_map()
  end

  defp normalize_ok_payload(value, action),
    do: %{"action" => Atom.to_string(action), "value" => inspect(value)}

  defp stringify_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stringify_value(value)} end)
    |> Map.new()
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(list) when is_list(list), do: Enum.map(list, &stringify_value/1)
  defp stringify_value(value), do: value

  defp apply_lock_state(state, %Signal{
         session_id: session_id,
         data: %{action: :lock_state, payload: payload}
       }) do
    window_ids = Map.get(state.session_windows, session_id, MapSet.new()) |> MapSet.to_list()
    owner = payload[:owner]

    Enum.reduce(window_ids, state, fn window_id, acc ->
      case Map.get(acc.windows, window_id) do
        nil ->
          acc

        info ->
          lock_token =
            cond do
              payload[:action] == :released -> nil
              owner == info.owner_id -> info.lock_token
              true -> nil
            end

          put_window(acc, %{info | lock_token: lock_token})
      end
    end)
  end

  defp apply_lock_state(state, _signal), do: state

  defp window_descriptor(info) do
    %{
      window_id: info.window_id,
      owner_id: info.owner_id,
      mode: info.mode,
      session_id: info.session_id,
      connected: info.connected,
      lock_token: info.lock_token
    }
  end

  defp short_id(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  defp get_param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
