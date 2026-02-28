defmodule JidoDocs.SignalBus do
  @moduledoc """
  Session-scoped signal subscription and fanout bus.

  Delivery model is best-effort with queue-aware dropping to avoid downstream
  subscriber overload.
  """

  use GenServer

  alias JidoDocs.{Error, Signal}

  @default_max_queue_len 200

  @type session_id :: String.t()

  @type state :: %{
          subscribers: %{optional(session_id()) => MapSet.t(pid())},
          monitors: %{optional(reference()) => {session_id(), pid()}},
          dropped_events: non_neg_integer(),
          max_queue_len: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec subscribe(GenServer.server(), session_id(), keyword()) :: :ok | {:error, Error.t()}
  def subscribe(server \\ __MODULE__, session_id, opts \\ []) do
    subscriber = Keyword.get(opts, :pid, self())
    GenServer.call(server, {:subscribe, session_id, subscriber})
  end

  @spec unsubscribe(GenServer.server(), session_id(), keyword()) :: :ok
  def unsubscribe(server \\ __MODULE__, session_id, opts \\ []) do
    subscriber = Keyword.get(opts, :pid, self())
    GenServer.call(server, {:unsubscribe, session_id, subscriber})
  end

  @spec broadcast(GenServer.server(), Signal.signal_type(), session_id(), map(), keyword()) ::
          {:ok, Signal.t(), map()} | {:error, Error.t()}
  def broadcast(server \\ __MODULE__, type, session_id, data, opts \\ []) do
    GenServer.call(server, {:broadcast, type, session_id, data, opts})
  end

  @spec subscribers(GenServer.server(), session_id()) :: [pid()]
  def subscribers(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:subscribers, session_id})
  end

  @impl true
  def init(opts) do
    state = %{
      subscribers: %{},
      monitors: %{},
      dropped_events: 0,
      max_queue_len: Keyword.get(opts, :max_queue_len, @default_max_queue_len)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, session_id, pid}, _from, state) do
    with :ok <- validate_session_id(session_id),
         :ok <- validate_pid(pid) do
      {state, _already_subscribed?} = ensure_subscriber(state, session_id, pid)
      {:reply, :ok, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:unsubscribe, session_id, pid}, _from, state) do
    subscribers = Map.get(state.subscribers, session_id, MapSet.new())
    updated_subscribers = MapSet.delete(subscribers, pid)

    state =
      if MapSet.size(updated_subscribers) == 0 do
        %{state | subscribers: Map.delete(state.subscribers, session_id)}
      else
        %{state | subscribers: Map.put(state.subscribers, session_id, updated_subscribers)}
      end

    {:reply, :ok, state}
  end

  def handle_call({:subscribers, session_id}, _from, state) do
    subscriber_list =
      state.subscribers
      |> Map.get(session_id, MapSet.new())
      |> MapSet.to_list()

    {:reply, subscriber_list, state}
  end

  def handle_call({:broadcast, type, session_id, data, opts}, _from, state) do
    with {:ok, signal} <- Signal.build(type, session_id, data, opts) do
      {state, delivered, dropped} = deliver_signal(state, signal)

      metrics = %{delivered: delivered, dropped: dropped, subscribers: delivered + dropped}

      if dropped > 0 do
        emit_signal_metrics(:dropped, signal, metrics)
      else
        emit_signal_metrics(:delivered, signal, metrics)
      end

      {:reply, {:ok, signal, metrics}, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      {session_id, ^pid} ->
        subscribers = Map.get(state.subscribers, session_id, MapSet.new())
        updated_subscribers = MapSet.delete(subscribers, pid)

        updated_topics =
          if MapSet.size(updated_subscribers) == 0 do
            Map.delete(state.subscribers, session_id)
          else
            Map.put(state.subscribers, session_id, updated_subscribers)
          end

        updated_state = %{
          state
          | subscribers: updated_topics,
            monitors: Map.delete(state.monitors, ref)
        }

        emit_cleanup(session_id, pid)
        {:noreply, updated_state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp deliver_signal(state, %Signal{} = signal) do
    subscribers = Map.get(state.subscribers, signal.session_id, MapSet.new())

    Enum.reduce(subscribers, {state, 0, 0}, fn pid, {acc_state, delivered, dropped} ->
      if not Process.alive?(pid) do
        {acc_state, delivered, dropped + 1}
      else
        queue_len = message_queue_len(pid)

        if queue_len > acc_state.max_queue_len do
          {
            %{acc_state | dropped_events: acc_state.dropped_events + 1},
            delivered,
            dropped + 1
          }
        else
          send(pid, Signal.to_message(signal))
          {acc_state, delivered + 1, dropped}
        end
      end
    end)
  end

  defp ensure_subscriber(state, session_id, pid) do
    current = Map.get(state.subscribers, session_id, MapSet.new())

    if MapSet.member?(current, pid) do
      {state, true}
    else
      ref = Process.monitor(pid)

      updated_state = %{
        state
        | subscribers: Map.put(state.subscribers, session_id, MapSet.put(current, pid)),
          monitors: Map.put(state.monitors, ref, {session_id, pid})
      }

      {updated_state, false}
    end
  end

  defp message_queue_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      _ -> 0
    end
  end

  defp validate_session_id(session_id) when is_binary(session_id) and session_id != "", do: :ok

  defp validate_session_id(session_id) do
    {:error,
     Error.new(:subscription_error, "session_id must be a non-empty string", %{
       session_id: session_id
     })}
  end

  defp validate_pid(pid) when is_pid(pid), do: :ok

  defp validate_pid(pid) do
    {:error, Error.new(:subscription_error, "subscriber must be a pid", %{pid: pid})}
  end

  defp emit_cleanup(session_id, pid) do
    emit_signal_metrics(:cleaned, %{session_id: session_id, pid: pid}, %{})
  end

  defp emit_signal_metrics(kind, signal_or_data, metrics) do
    event = [:jido_docs, :signal_bus, kind]

    metadata =
      case signal_or_data do
        %Signal{} = signal ->
          Map.merge(metrics, %{
            session_id: signal.session_id,
            type: signal.type,
            schema_version: signal.schema_version
          })

        %{} = data ->
          Map.merge(metrics, data)
      end

    if Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :execute, 3) do
      apply(:telemetry, :execute, [event, %{}, metadata])
    end

    :ok
  end
end
