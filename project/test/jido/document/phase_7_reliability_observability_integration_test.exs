defmodule Jido.Document.Phase7ReliabilityObservabilityIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, Signal}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    session_id = "phase7-reliability-" <> uniq

    {:ok, agent} =
      Agent.start_link(
        session_id: session_id,
        render_circuit_threshold: 2,
        render_circuit_cooldown_ms: 120
      )

    :ok = Agent.subscribe(agent)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase7_reliability_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Reliability\"\n---\nBody 0\n")

    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts())
    assert_receive {:jido_document_signal, %Signal{type: :loaded, session_id: ^session_id}}, 500

    on_exit(fn ->
      if Process.alive?(agent) do
        _ = catch_exit(GenServer.stop(agent, :normal))
      end

      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, session_id: session_id}
  end

  test "opens render circuit under failure bursts and recovers after cooldown", ctx do
    session_id = ctx.session_id

    assert %{status: :ok} =
             Agent.command(ctx.agent, :render, %{render_opts: %{adapter: :unknown}})

    assert %{status: :ok} =
             Agent.command(ctx.agent, :render, %{render_opts: %{adapter: :unknown}})

    assert_receive {:jido_document_signal,
                    %Signal{
                      session_id: ^session_id,
                      type: :updated,
                      data: %{action: :degraded_mode}
                    }},
                   500

    assert %{status: :error, error: open_error} = Agent.command(ctx.agent, :render, %{})
    assert open_error.code == :busy
    assert open_error.details.degraded_mode == true
    assert open_error.details.retry_after_ms > 0

    Process.sleep(160)

    assert %{status: :ok} = Agent.command(ctx.agent, :render, %{})

    assert_receive {:jido_document_signal,
                    %Signal{
                      session_id: ^session_id,
                      type: :updated,
                      data: %{action: :degraded_mode_recovered}
                    }},
                   500
  end

  test "emits connectivity health signals for subscribe/unsubscribe transitions", ctx do
    session_id = ctx.session_id
    subscriber = spawn(fn -> Process.sleep(300) end)

    assert :ok = Agent.subscribe(ctx.agent, subscriber)

    assert_receive {:jido_document_signal,
                    %Signal{
                      session_id: ^session_id,
                      type: :updated,
                      data: %{action: :connectivity, payload: %{transition: :subscribed}}
                    }},
                   500

    assert :ok = Agent.unsubscribe(ctx.agent, subscriber)

    assert_receive {:jido_document_signal,
                    %Signal{
                      session_id: ^session_id,
                      type: :updated,
                      data: %{action: :connectivity, payload: %{transition: :unsubscribed}}
                    }},
                   500
  end

  test "publishes agent telemetry metrics and complete audit trace entries", ctx do
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Updated body\n"})
    assert %{status: :ok} = Agent.command(ctx.agent, :render, %{})

    if Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :attach, 4) do
      test_pid = self()

      handler_id =
        "phase7-agent-metrics-" <> Integer.to_string(System.unique_integer([:positive]))

      :ok =
        apply(:telemetry, :attach, [
          handler_id,
          [:jido_document, :agent, :command],
          fn event, measurements, metadata, _config ->
            send(test_pid, {:agent_metric, event, measurements, metadata})
          end,
          %{}
        ])

      on_exit(fn -> apply(:telemetry, :detach, [handler_id]) end)

      assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Updated body\n"})
      assert %{status: :ok} = Agent.command(ctx.agent, :render, %{})

      assert_receive {:agent_metric, [:jido_document, :agent, :command], measurements1,
                      metadata1},
                     500

      assert_receive {:agent_metric, [:jido_document, :agent, :command], measurements2,
                      metadata2},
                     500

      for measurements <- [measurements1, measurements2] do
        assert is_integer(measurements.duration_us)
        assert measurements.duration_us >= 0
      end

      for metadata <- [metadata1, metadata2] do
        assert metadata.session_id == ctx.session_id
        assert metadata.status in [:ok, :error]
        assert is_map(metadata.queue_stats)
      end
    end

    trace = Agent.export_trace(ctx.agent, limit: 20)
    assert length(trace.audit_events) >= 2
    assert Enum.any?(trace.audit_events, fn event -> event.action == :render end)
  end

  defp fs_opts, do: [context_options: %{workspace_root: "/"}]
end
