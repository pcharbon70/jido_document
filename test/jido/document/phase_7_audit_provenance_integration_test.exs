defmodule Jido.Document.Phase7AuditProvenanceIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.Agent

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    session_id = "phase7-audit-" <> uniq
    test_pid = self()

    sink = fn event ->
      send(test_pid, {:audit_event, event})
      :ok
    end

    {:ok, agent} = Agent.start_link(session_id: session_id, audit_sinks: [sink], audit_limit: 100)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase7_audit_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Audit\"\n---\nBody 0\n")

    on_exit(fn ->
      if Process.alive?(agent) do
        _ = catch_exit(GenServer.stop(agent, :normal))
      end

      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, session_id: session_id, source_path: source_path}
  end

  test "emits structured audit events with shared correlation IDs", ctx do
    correlation_id = "corr-phase7-audit"
    actor = %{id: "editor-1", roles: ["editor"]}

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :load,
               %{path: ctx.source_path},
               correlation_id: correlation_id,
               actor: actor,
               source: :api,
               context_options: %{workspace_root: "/"}
             )

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :update_body,
               %{body: "Body 1\n"},
               correlation_id: correlation_id,
               actor: actor,
               source: :api
             )

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :save,
               %{path: ctx.source_path},
               correlation_id: correlation_id,
               actor: actor,
               source: :api,
               context_options: %{workspace_root: "/"}
             )

    assert_receive {:audit_event, load_event}, 500
    assert_receive {:audit_event, update_event}, 500
    assert_receive {:audit_event, save_event}, 500

    for event <- [load_event, update_event, save_event] do
      assert event.schema_version == 1
      assert event.event_type == :action
      assert event.status == :ok
      assert event.session_id == ctx.session_id
      assert event.correlation_id == correlation_id
      assert event.source == "api"
      assert event.actor.id == "editor-1"
    end
  end

  test "exports trace bundle with lineage and source annotations", ctx do
    actor = %{id: "editor-2", roles: ["editor"]}

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :load,
               %{path: ctx.source_path},
               actor: actor,
               source: :api,
               context_options: %{workspace_root: "/"}
             )

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :update_frontmatter,
               %{changes: %{owner: "ops"}},
               actor: actor,
               source: :automation
             )

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :save,
               %{path: ctx.source_path},
               actor: actor,
               source: :api,
               context_options: %{workspace_root: "/"}
             )

    trace = Agent.export_trace(ctx.agent, limit: 20)

    assert trace.session_id == ctx.session_id
    assert is_map(trace.latest_revision_entry)
    assert is_list(trace.history)
    assert is_list(trace.audit_events)

    assert Enum.any?(trace.history, &(&1.source in ["api", "automation"]))

    save_event = Enum.find(trace.audit_events, fn event -> event.action == :save end)
    assert save_event != nil
    assert is_map(save_event.metadata.lineage)
    assert Map.has_key?(save_event.metadata.lineage, :parent_revision_id)
  end
end
