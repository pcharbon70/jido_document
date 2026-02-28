defmodule Jido.Document.SessionRegistry do
  @moduledoc """
  Session discovery, lifecycle, and ownership registry.

  Responsibilities:
  - Deterministic session ID generation for file-backed sessions
  - Explicit and lazy session creation
  - Stale session cleanup
  - Lock ownership semantics with optimistic token validation
  """

  use GenServer

  alias Jido.Document.{Error, SignalBus}

  @type session_id :: String.t()
  @type owner_id :: String.t()

  @type session_info :: %{
          session_id: session_id(),
          pid: pid(),
          path: Path.t() | nil,
          lock_token: String.t() | nil,
          lock_owner: owner_id() | nil,
          lock_revision: non_neg_integer(),
          started_at_ms: non_neg_integer(),
          last_seen_ms: non_neg_integer()
        }

  @default_idle_timeout_ms 30 * 60 * 1000
  @default_cleanup_interval_ms 60_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec session_id_for_path(Path.t()) :: session_id()
  def session_id_for_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    digest =
      expanded
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 20)

    "file-" <> digest
  end

  @spec ensure_session(GenServer.server(), session_id(), keyword()) ::
          {:ok, session_info()} | {:error, Error.t()}
  def ensure_session(server \\ __MODULE__, session_id, opts \\ []) do
    GenServer.call(server, {:ensure_session, session_id, opts})
  end

  @spec ensure_session_by_path(GenServer.server(), Path.t(), keyword()) ::
          {:ok, session_info()} | {:error, Error.t()}
  def ensure_session_by_path(server \\ __MODULE__, path, opts \\ []) do
    GenServer.call(server, {:ensure_session_by_path, path, opts})
  end

  @spec fetch_session(GenServer.server(), session_id()) ::
          {:ok, session_info()} | {:error, Error.t()}
  def fetch_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:fetch_session, session_id})
  end

  @spec list_sessions(GenServer.server()) :: [session_info()]
  def list_sessions(server \\ __MODULE__) do
    GenServer.call(server, :list_sessions)
  end

  @spec acquire_lock(GenServer.server(), session_id(), owner_id(), keyword()) ::
          {:ok, %{lock_token: String.t(), lock_revision: non_neg_integer(), owner: owner_id()}}
          | {:error, Error.t()}
  def acquire_lock(server \\ __MODULE__, session_id, owner_id, opts \\ []) do
    GenServer.call(server, {:acquire_lock, session_id, owner_id, opts})
  end

  @spec validate_lock(GenServer.server(), session_id(), String.t()) :: :ok | {:error, Error.t()}
  def validate_lock(server \\ __MODULE__, session_id, lock_token) do
    GenServer.call(server, {:validate_lock, session_id, lock_token})
  end

  @spec release_lock(GenServer.server(), session_id(), String.t()) :: :ok | {:error, Error.t()}
  def release_lock(server \\ __MODULE__, session_id, lock_token) do
    GenServer.call(server, {:release_lock, session_id, lock_token})
  end

  @spec force_takeover(GenServer.server(), session_id(), owner_id(), keyword()) ::
          {:ok,
           %{
             lock_token: String.t(),
             lock_revision: non_neg_integer(),
             owner: owner_id(),
             previous_owner: owner_id() | nil
           }}
          | {:error, Error.t()}
  def force_takeover(server \\ __MODULE__, session_id, owner_id, opts \\ []) do
    GenServer.call(server, {:force_takeover, session_id, owner_id, opts})
  end

  @spec reclaim_idle(GenServer.server(), non_neg_integer()) :: {:ok, [session_id()]}
  def reclaim_idle(server \\ __MODULE__, max_idle_ms) do
    GenServer.call(server, {:reclaim_idle, max_idle_ms})
  end

  @spec touch(GenServer.server(), session_id()) :: :ok
  def touch(server \\ __MODULE__, session_id) do
    GenServer.cast(server, {:touch, session_id})
  end

  @impl true
  def init(opts) do
    state = %{
      sessions: %{},
      path_index: %{},
      monitors: %{},
      session_supervisor: Keyword.get(opts, :session_supervisor, Jido.Document.SessionSupervisor),
      signal_bus: Keyword.get(opts, :signal_bus, SignalBus),
      idle_timeout_ms: Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:ensure_session, session_id, opts}, _from, state) do
    path = Keyword.get(opts, :path)

    with :ok <- validate_session_id(session_id),
         {:ok, state, info} <- ensure_started(state, session_id, path, opts) do
      {:reply, {:ok, info}, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:ensure_session_by_path, path, opts}, _from, state) do
    with {:ok, expanded_path} <- validate_path(path),
         session_id <- path_session_id(state, expanded_path),
         {:ok, state, info} <- ensure_started(state, session_id, expanded_path, opts) do
      {:reply, {:ok, info}, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:fetch_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, Error.new(:not_found, "session not found", %{session_id: session_id})},
         state}

      info ->
        state = touch_info(state, session_id)
        {:reply, {:ok, info}, state}
    end
  end

  def handle_call(:list_sessions, _from, state) do
    {:reply, state.sessions |> Map.values() |> Enum.sort_by(& &1.started_at_ms), state}
  end

  def handle_call({:acquire_lock, session_id, owner_id, opts}, _from, state) do
    with {:ok, session} <- fetch_session_info(state, session_id),
         :ok <- validate_owner(owner_id),
         {:ok, updated_session, payload} <- do_acquire_lock(session, owner_id, opts) do
      state = put_session(state, updated_session)
      emit_lock_signal(state, session_id, payload)
      {:reply, {:ok, payload}, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:validate_lock, session_id, lock_token}, _from, state) do
    with {:ok, session} <- fetch_session_info(state, session_id),
         :ok <- ensure_lock_token(session, lock_token) do
      {:reply, :ok, touch_info(state, session_id)}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:release_lock, session_id, lock_token}, _from, state) do
    with {:ok, session} <- fetch_session_info(state, session_id),
         :ok <- ensure_lock_token(session, lock_token) do
      updated_session = %{
        session
        | lock_token: nil,
          lock_owner: nil,
          lock_revision: session.lock_revision + 1,
          last_seen_ms: now_ms()
      }

      state = put_session(state, updated_session)

      emit_lock_signal(state, session_id, %{
        action: :released,
        owner: nil,
        lock_revision: updated_session.lock_revision
      })

      {:reply, :ok, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:force_takeover, session_id, owner_id, opts}, _from, state) do
    with {:ok, session} <- fetch_session_info(state, session_id),
         :ok <- validate_owner(owner_id) do
      previous_owner = session.lock_owner
      lock_token = new_lock_token(session_id, owner_id)

      updated_session =
        %{
          session
          | lock_token: lock_token,
            lock_owner: owner_id,
            lock_revision: session.lock_revision + 1,
            last_seen_ms: now_ms()
        }

      state = put_session(state, updated_session)

      payload = %{
        lock_token: lock_token,
        lock_revision: updated_session.lock_revision,
        owner: owner_id,
        previous_owner: previous_owner,
        reason: Keyword.get(opts, :reason)
      }

      emit_lock_signal(state, session_id, Map.put(payload, :action, :takeover))
      {:reply, {:ok, payload}, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:reclaim_idle, max_idle_ms}, _from, state)
      when is_integer(max_idle_ms) and max_idle_ms >= 0 do
    {state, removed_ids} = reclaim_idle_sessions(state, max_idle_ms)
    {:reply, {:ok, removed_ids}, state}
  end

  @impl true
  def handle_cast({:touch, session_id}, state) do
    {:noreply, touch_info(state, session_id)}
  end

  @impl true
  def handle_info(:cleanup_idle_sessions, state) do
    {state, _removed} = reclaim_idle_sessions(state, state.idle_timeout_ms)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      session_id ->
        state = remove_session(state, session_id)
        {:noreply, %{state | monitors: Map.delete(state.monitors, ref)}}
    end
  end

  defp ensure_started(state, session_id, path, opts) do
    case Map.get(state.sessions, session_id) do
      nil ->
        start_new_session(state, session_id, path, opts)

      info ->
        updated_info = maybe_attach_path(info, path)

        state =
          state
          |> put_session(updated_info)
          |> put_path_index(path, session_id)
          |> touch_info(session_id)

        {:ok, state, updated_info}
    end
  end

  defp start_new_session(state, session_id, path, opts) do
    agent_opts =
      [session_id: session_id, signal_bus: state.signal_bus]
      |> maybe_put(:path, path)
      |> maybe_put(:name, Keyword.get(opts, :name))

    case DynamicSupervisor.start_child(
           state.session_supervisor,
           {Jido.Document.Agent, agent_opts}
         ) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        info = %{
          session_id: session_id,
          pid: pid,
          path: path,
          lock_token: nil,
          lock_owner: nil,
          lock_revision: 0,
          started_at_ms: now_ms(),
          last_seen_ms: now_ms()
        }

        state =
          state
          |> put_session(info)
          |> put_path_index(path, session_id)
          |> put_monitor(ref, session_id)

        {:ok, state, info}

      {:error, {:already_started, pid}} ->
        ref = Process.monitor(pid)

        info = %{
          session_id: session_id,
          pid: pid,
          path: path,
          lock_token: nil,
          lock_owner: nil,
          lock_revision: 0,
          started_at_ms: now_ms(),
          last_seen_ms: now_ms()
        }

        state =
          state
          |> put_session(info)
          |> put_path_index(path, session_id)
          |> put_monitor(ref, session_id)

        {:ok, state, info}

      {:error, reason} ->
        {:error,
         Error.new(:internal, "failed to start session", %{session_id: session_id, reason: reason})}
    end
  end

  defp do_acquire_lock(session, owner_id, opts) do
    expected = Keyword.get(opts, :expected_token)

    cond do
      expected != nil and session.lock_token != expected ->
        {:error,
         Error.new(:conflict, "stale lock token", %{
           session_id: session.session_id,
           expected_token: expected,
           actual_token: session.lock_token
         })}

      session.lock_token == nil ->
        grant_lock(session, owner_id)

      session.lock_owner == owner_id ->
        if Keyword.get(opts, :rotate_token, false) do
          grant_lock(session, owner_id)
        else
          payload = %{
            lock_token: session.lock_token,
            lock_revision: session.lock_revision,
            owner: owner_id
          }

          {:ok, %{session | last_seen_ms: now_ms()}, payload}
        end

      true ->
        {:error,
         Error.new(:conflict, "session lock held by another owner", %{
           session_id: session.session_id,
           owner: session.lock_owner,
           requested_owner: owner_id
         })}
    end
  end

  defp grant_lock(session, owner_id) do
    lock_token = new_lock_token(session.session_id, owner_id)

    updated =
      %{
        session
        | lock_token: lock_token,
          lock_owner: owner_id,
          lock_revision: session.lock_revision + 1,
          last_seen_ms: now_ms()
      }

    payload = %{lock_token: lock_token, lock_revision: updated.lock_revision, owner: owner_id}
    {:ok, updated, payload}
  end

  defp ensure_lock_token(session, token) when is_binary(token) and token != "" do
    cond do
      session.lock_token == nil ->
        {:error,
         Error.new(:conflict, "session has no active lock", %{session_id: session.session_id})}

      session.lock_token != token ->
        {:error,
         Error.new(:conflict, "invalid lock token", %{
           session_id: session.session_id,
           provided_token: token
         })}

      true ->
        :ok
    end
  end

  defp ensure_lock_token(_session, token) do
    {:error,
     Error.new(:invalid_params, "lock_token must be non-empty binary", %{lock_token: token})}
  end

  defp fetch_session_info(state, session_id) do
    case Map.get(state.sessions, session_id) do
      nil -> {:error, Error.new(:not_found, "session not found", %{session_id: session_id})}
      info -> {:ok, info}
    end
  end

  defp reclaim_idle_sessions(state, max_idle_ms) do
    now = now_ms()

    stale_ids =
      state.sessions
      |> Enum.filter(fn {_id, info} -> now - info.last_seen_ms >= max_idle_ms end)
      |> Enum.map(fn {id, _info} -> id end)

    Enum.reduce(stale_ids, {state, []}, fn session_id, {acc_state, removed} ->
      acc_state =
        case Map.get(acc_state.sessions, session_id) do
          nil ->
            acc_state

          %{pid: pid} ->
            if Process.alive?(pid),
              do: DynamicSupervisor.terminate_child(acc_state.session_supervisor, pid)

            remove_session(acc_state, session_id)
        end

      {acc_state, [session_id | removed]}
    end)
    |> then(fn {next_state, removed} -> {next_state, Enum.reverse(removed)} end)
  end

  defp emit_lock_signal(state, session_id, payload) do
    SignalBus.broadcast(
      state.signal_bus,
      :updated,
      session_id,
      %{action: :lock_state, payload: payload},
      source: :session_registry
    )

    :ok
  rescue
    _ -> :ok
  end

  defp touch_info(state, session_id) do
    case Map.get(state.sessions, session_id) do
      nil -> state
      info -> put_session(state, %{info | last_seen_ms: now_ms()})
    end
  end

  defp remove_session(state, session_id) do
    session = Map.get(state.sessions, session_id)

    state
    |> Map.update!(:sessions, &Map.delete(&1, session_id))
    |> Map.update!(:path_index, fn index ->
      case session do
        %{path: path} when is_binary(path) -> Map.delete(index, path)
        _ -> index
      end
    end)
  end

  defp put_session(state, info),
    do: %{state | sessions: Map.put(state.sessions, info.session_id, info)}

  defp put_path_index(state, nil, _session_id), do: state

  defp put_path_index(state, path, session_id),
    do: %{state | path_index: Map.put(state.path_index, path, session_id)}

  defp put_monitor(state, ref, session_id),
    do: %{state | monitors: Map.put(state.monitors, ref, session_id)}

  defp path_session_id(state, path) do
    case Map.get(state.path_index, path) do
      nil -> session_id_for_path(path)
      session_id -> session_id
    end
  end

  defp maybe_attach_path(info, nil), do: info
  defp maybe_attach_path(%{path: nil} = info, path), do: %{info | path: path}
  defp maybe_attach_path(info, _path), do: info

  defp new_lock_token(session_id, owner_id) do
    entropy = Integer.to_string(System.unique_integer([:positive]))

    [session_id, owner_id, entropy]
    |> Enum.join(":")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 24)
  end

  defp validate_session_id(session_id) when is_binary(session_id) and session_id != "", do: :ok

  defp validate_session_id(session_id) do
    {:error,
     Error.new(:invalid_params, "session_id must be non-empty binary", %{session_id: session_id})}
  end

  defp validate_path(path) when is_binary(path), do: {:ok, Path.expand(path)}

  defp validate_path(path) do
    {:error, Error.new(:invalid_params, "path must be a string", %{path: path})}
  end

  defp validate_owner(owner) when is_binary(owner) and owner != "", do: :ok

  defp validate_owner(owner) do
    {:error, Error.new(:invalid_params, "owner must be non-empty binary", %{owner: owner})}
  end

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :cleanup_idle_sessions, interval_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)
end
