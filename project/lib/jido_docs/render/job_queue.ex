defmodule JidoDocs.Render.JobQueue do
  @moduledoc """
  Debounced render queue with superseded-job cancellation.

  Queue policy:
  - One pending job per session; newer revisions replace older queued jobs.
  - Bounded total queue size to prevent saturation.
  - Best-effort delivery to a caller-provided `notify_pid`.
  """

  use GenServer

  alias JidoDocs.{Error, Renderer}
  alias JidoDocs.Render.Metrics

  @default_max_queue_size 128
  @default_debounce_ms 120

  @type job :: %{
          id: String.t(),
          session_id: String.t(),
          revision: non_neg_integer(),
          markdown: String.t(),
          render_opts: keyword() | map(),
          notify_pid: pid() | nil,
          decision: map() | nil,
          inserted_at: integer()
        }

  @type state :: %{
          jobs: %{optional(String.t()) => job()},
          timers: %{optional(String.t()) => reference()},
          max_queue_size: pos_integer(),
          debounce_ms: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec enqueue(GenServer.server(), String.t(), non_neg_integer(), String.t(), keyword() | map()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def enqueue(server \\ __MODULE__, session_id, revision, markdown, opts \\ []) do
    GenServer.call(server, {:enqueue, session_id, revision, markdown, opts})
  end

  @spec cancel_superseded(GenServer.server(), String.t(), non_neg_integer()) :: :ok
  def cancel_superseded(server \\ __MODULE__, session_id, revision) do
    GenServer.call(server, {:cancel_superseded, session_id, revision})
  end

  @spec stats(GenServer.server()) :: map()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       jobs: %{},
       timers: %{},
       max_queue_size: Keyword.get(opts, :max_queue_size, @default_max_queue_size),
       debounce_ms: Keyword.get(opts, :debounce_ms, @default_debounce_ms)
     }}
  end

  @impl true
  def handle_call({:enqueue, session_id, revision, markdown, opts}, _from, state) do
    with :ok <- validate_enqueue(session_id, revision, markdown) do
      opts = normalize_opts(opts)

      queue_size = map_size(state.jobs)
      existing_for_session? = Map.has_key?(state.jobs, session_id)

      if queue_size >= state.max_queue_size and not existing_for_session? do
        Metrics.increment(:queue_dropped)

        {:reply,
         {:error,
          Error.new(:busy, "render queue is full", %{
            queue_size: queue_size,
            max: state.max_queue_size
          })}, state}
      else
        state = cancel_timer(state, session_id)

        job = %{
          id: job_id(session_id, revision),
          session_id: session_id,
          revision: revision,
          markdown: markdown,
          render_opts: Map.get(opts, :render_opts, %{}),
          notify_pid: Map.get(opts, :notify_pid),
          decision: Map.get(opts, :decision),
          inserted_at: System.system_time(:millisecond)
        }

        timer = Process.send_after(self(), {:run_job, session_id, revision}, state.debounce_ms)

        state = %{
          state
          | jobs: Map.put(state.jobs, session_id, job),
            timers: Map.put(state.timers, session_id, timer)
        }

        Metrics.increment(:queue_enqueued)

        {:reply, {:ok, job.id}, state}
      end
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:cancel_superseded, session_id, revision}, _from, state) do
    state =
      case Map.get(state.jobs, session_id) do
        %{revision: queued_revision} when queued_revision < revision ->
          Metrics.increment(:queue_canceled)
          cancel_timer(remove_job(state, session_id), session_id)

        _ ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       queued_sessions: map_size(state.jobs),
       max_queue_size: state.max_queue_size,
       debounce_ms: state.debounce_ms,
       counters: Metrics.snapshot()
     }, state}
  end

  @impl true
  def handle_info({:run_job, session_id, expected_revision}, state) do
    state = %{state | timers: Map.delete(state.timers, session_id)}

    case Map.get(state.jobs, session_id) do
      %{revision: ^expected_revision} = job ->
        state = remove_job(state, session_id)
        execute_job(job)
        Metrics.increment(:queue_completed)
        {:noreply, state}

      %{revision: newer_revision} when newer_revision > expected_revision ->
        Metrics.increment(:queue_canceled)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp execute_job(job) do
    result = Renderer.render(job.markdown, job.render_opts)

    if is_pid(job.notify_pid) do
      send(
        job.notify_pid,
        {:jido_docs_render_job, job.session_id, job.revision, result,
         %{job_id: job.id, decision: job.decision}}
      )
    end

    :ok
  end

  defp validate_enqueue(session_id, revision, markdown) do
    cond do
      not (is_binary(session_id) and session_id != "") ->
        {:error,
         Error.new(:invalid_params, "session_id must be non-empty binary", %{
           session_id: session_id
         })}

      not (is_integer(revision) and revision >= 0) ->
        {:error,
         Error.new(:invalid_params, "revision must be non-negative integer", %{revision: revision})}

      not is_binary(markdown) ->
        {:error, Error.new(:invalid_params, "markdown must be a string", %{markdown: markdown})}

      true ->
        :ok
    end
  end

  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}

  defp job_id(session_id, revision) do
    "job-#{session_id}-#{revision}-#{System.unique_integer([:positive])}"
  end

  defp remove_job(state, session_id), do: %{state | jobs: Map.delete(state.jobs, session_id)}

  defp cancel_timer(state, session_id) do
    case Map.pop(state.timers, session_id) do
      {nil, _timers} ->
        state

      {ref, timers} ->
        Process.cancel_timer(ref)
        %{state | timers: timers}
    end
  end
end
