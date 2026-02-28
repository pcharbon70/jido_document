defmodule JidoDocs.Phase4SchedulingFallbackIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoDocs.{Agent, Error, Signal}
  alias JidoDocs.Render.JobQueue

  test "queue saturation and superseded cancellation keep latest render jobs" do
    queue_name = {:global, {:phase4_queue, System.unique_integer([:positive])}}
    {:ok, queue_pid} = JobQueue.start_link(name: queue_name, max_queue_size: 2, debounce_ms: 20)

    on_exit(fn ->
      if Process.alive?(queue_pid), do: GenServer.stop(queue_pid, :normal)
    end)

    assert {:ok, _job_a1} =
             JobQueue.enqueue(queue_name, "session-a", 1, "# a1\n", notify_pid: self())

    assert {:ok, _job_a2} =
             JobQueue.enqueue(queue_name, "session-a", 2, "# a2\n", notify_pid: self())

    assert {:ok, _job_b1} =
             JobQueue.enqueue(queue_name, "session-b", 1, "# b1\n", notify_pid: self())

    assert {:error, %Error{code: :busy}} =
             JobQueue.enqueue(queue_name, "session-c", 1, "# c1\n", notify_pid: self())

    assert_receive {:jido_docs_render_job, "session-a", 2, {:ok, _preview}, _meta}, 500
    assert_receive {:jido_docs_render_job, "session-b", 1, {:ok, _preview}, _meta}, 500
    refute_receive {:jido_docs_render_job, "session-a", 1, _result, _meta}, 50

    stats = JobQueue.stats(queue_name)
    assert stats.counters.queue_enqueued >= 3
    assert stats.counters.queue_dropped >= 1
  end

  test "renderer failure triggers fallback preview then recovery signal on success" do
    session_id = "phase4-fallback-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)
    :ok = Agent.subscribe(agent)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_docs_phase4_" <> session_id)
    :ok = File.mkdir_p(tmp_dir)
    path = Path.join(tmp_dir, "doc.md")
    :ok = File.write(path, "---\ntitle: \"Fallback\"\n---\n# Start\n")

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    load_opts = [context_options: %{workspace_root: "/"}]

    assert %{status: :ok} = Agent.command(agent, :load, %{path: path}, load_opts)
    assert_receive {:jido_docs_signal, %Signal{type: :loaded, session_id: ^session_id}}, 500

    # Force render adapter failure to activate fallback mode.
    assert %{status: :ok, value: %{preview: fallback_preview}} =
             Agent.command(agent, :render, %{render_opts: %{adapter: :unknown}})

    assert fallback_preview.metadata.fallback == true

    assert_receive {:jido_docs_signal, %Signal{type: :failed, session_id: ^session_id}}, 500
    assert_receive {:jido_docs_signal, %Signal{type: :rendered, session_id: ^session_id}}, 500

    # Recover with normal render options.
    assert %{status: :ok, value: %{preview: normal_preview}} = Agent.command(agent, :render, %{})
    refute Map.get(normal_preview.metadata, :fallback, false)

    assert_receive {:jido_docs_signal, %Signal{type: :rendered, session_id: ^session_id}}, 500

    assert_receive {:jido_docs_signal,
                    %Signal{
                      type: :updated,
                      session_id: ^session_id,
                      data: %{action: :render_recovered}
                    }},
                   500
  end
end
