defmodule Jido.Document.Phase8PostReleaseVerificationIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, Triage}

  test "validates first-day telemetry events and command error budget baseline" do
    root_dir = tmp_dir("phase8_post_release_metrics")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "metrics.md")
    File.write!(source_path, "---\ntitle: \"Telemetry\"\n---\nBody\n")

    session_id = "phase8-post-release-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
    end)

    telemetry_available? =
      Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :attach, 4)

    events =
      if telemetry_available? do
        attach_telemetry_handler(self(), session_id)
      else
        nil
      end

    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts())

    for index <- 1..5 do
      assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "Body #{index}\n"})
      assert %{status: :ok} = Agent.command(agent, :render, %{})
    end

    assert %{status: :ok} = Agent.command(agent, :save, %{path: source_path}, fs_opts())

    if telemetry_available? do
      expected_events = 12
      metrics = collect_metrics(expected_events, [])
      assert length(metrics) == expected_events

      for {_event, measurements, metadata} <- metrics do
        assert is_integer(measurements.duration_us)
        assert measurements.duration_us >= 0
        assert metadata.session_id == session_id
        assert metadata.status in [:ok, :error]
      end

      error_events =
        Enum.count(metrics, fn {_event, _measurements, metadata} -> metadata.status == :error end)

      error_rate = error_events / expected_events
      assert error_rate <= 0.05

      detach_telemetry_handler(events.handler_id)
    end
  end

  test "validates published sample commands run as documented" do
    {minimal_output, minimal_status} = run_mix(["run", "examples/minimal_api_sample.exs"])
    assert minimal_status == 0
    assert minimal_output =~ "session_id="
    assert minimal_output =~ "saved_bytes="

    {concurrency_output, concurrency_status} =
      run_mix(["run", "examples/session_concurrency_sample.exs"])

    assert concurrency_status == 0
    assert concurrency_output =~ "session_started="
    assert concurrency_output =~ "lock_released=true"

    {recovery_output, recovery_status} = run_mix(["run", "examples/crash_recovery_sample.exs"])
    assert recovery_status == 0
    assert recovery_output =~ "recovery_pending=true"
    assert recovery_output =~ "recovered_body=Unsaved change"
  end

  test "validates issue intake and triage loop produces prioritized follow-up output" do
    root_dir = tmp_dir("phase8_post_release_triage")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    issues = [
      %{
        id: "REL-100",
        summary: "save operation conflict after reconnect",
        component: "persistence",
        severity: :high,
        frequency: 8,
        reproducible: true
      },
      %{
        id: "REL-101",
        summary: "migration report typo",
        component: "docs",
        severity: :low,
        frequency: 1,
        reproducible: true
      },
      %{
        id: "REL-102",
        summary: "checkpoint recovery mismatch",
        component: "recovery",
        severity: :critical,
        frequency: 2,
        reproducible: true
      }
    ]

    prioritized = Triage.prioritize(issues)
    assert Enum.at(prioritized, 0).id == "REL-102"
    assert Enum.at(prioritized, 1).id == "REL-100"
    assert Enum.at(prioritized, 2).id == "REL-101"

    issues_path = Path.join(root_dir, "issues.exs")
    File.write!(issues_path, inspect(issues, pretty: true, limit: :infinity) <> "\n")

    report_path = Path.join(root_dir, "triage.md")

    {task_output, task_status} =
      run_mix([
        "jido.triage_report",
        "--input",
        issues_path,
        "--output",
        report_path,
        "--min-score",
        "20"
      ])

    assert task_status == 0
    assert task_output =~ "wrote triage report"
    report = File.read!(report_path)
    assert report =~ "REL-102"
    assert report =~ "REL-100"
    refute report =~ "REL-101"
  end

  defp attach_telemetry_handler(test_pid, session_id) do
    handler_id = "phase8-post-release-" <> session_id

    :ok =
      apply(:telemetry, :attach, [
        handler_id,
        [:jido_document, :agent, :command],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:post_release_metric, event, measurements, metadata})
        end,
        %{}
      ])

    %{handler_id: handler_id}
  end

  defp detach_telemetry_handler(handler_id) do
    apply(:telemetry, :detach, [handler_id])
  end

  defp collect_metrics(0, acc), do: Enum.reverse(acc)

  defp collect_metrics(remaining, acc) do
    receive do
      {:post_release_metric, event, measurements, metadata} ->
        collect_metrics(remaining - 1, [{event, measurements, metadata} | acc])
    after
      1_000 ->
        Enum.reverse(acc)
    end
  end

  defp run_mix(args) do
    System.cmd("mix", args,
      cd: project_root(),
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "test"}]
    )
  end

  defp fs_opts, do: [context_options: %{workspace_root: "/"}]

  defp project_root do
    Path.expand("../../..", __DIR__)
  end

  defp tmp_dir(prefix) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    Path.join(System.tmp_dir!(), "jido_document_#{prefix}_#{suffix}")
  end
end
