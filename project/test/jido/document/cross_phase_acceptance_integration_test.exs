defmodule Jido.Document.CrossPhaseAcceptanceSchema do
  @behaviour Jido.Document.Schema

  alias Jido.Document.Field

  @impl true
  def fields do
    [
      %Field{name: :title, type: :string, required: true},
      %Field{name: :priority, type: :integer, required: true},
      %Field{name: :owner, type: :string, required: false}
    ]
  end
end

defmodule Jido.Document.CrossPhaseAcceptanceIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, Document, SessionRegistry, Signal, SignalBus}

  test "X-1 schema-driven document can be edited with concurrent clients and saved without data loss" do
    root_dir = tmp_dir("x1")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "x1.md")
    File.write!(source_path, "---\ntitle: \"X1\"\npriority: 1\n---\nBody 1\n")

    registry_name = :"x1_registry_#{System.unique_integer([:positive])}"
    {:ok, registry} = SessionRegistry.start_link(name: registry_name)

    {:ok, session} = SessionRegistry.ensure_session_by_path(registry, source_path)
    session_id = session.session_id

    assert {:ok, _lock_a} = SessionRegistry.acquire_lock(registry, session_id, "client-a")
    assert {:error, conflict} = SessionRegistry.acquire_lock(registry, session_id, "client-b")
    assert conflict.code == :conflict
    assert conflict.details.owner == "client-a"

    assert %{status: :ok} = Agent.command(session.pid, :load, %{path: source_path}, fs_opts("/"))

    assert %{status: :ok} =
             Agent.command(session.pid, :update_frontmatter, %{changes: %{owner: "client-a"}})

    assert {:ok, takeover} =
             SessionRegistry.force_takeover(registry, session_id, "client-b", reason: "handoff")

    assert takeover.owner == "client-b"

    assert %{status: :ok} =
             Agent.command(session.pid, :update_body, %{body: "Body by client b\n"})

    assert %{status: :ok} = Agent.command(session.pid, :save, %{path: source_path}, fs_opts("/"))
    assert :ok = SessionRegistry.release_lock(registry, session_id, takeover.lock_token)

    {:ok, parsed} =
      Document.parse(File.read!(source_path),
        path: source_path,
        schema: Jido.Document.CrossPhaseAcceptanceSchema
      )

    assert parsed.frontmatter["title"] == "X1"
    assert parsed.frontmatter["priority"] == 1
    assert parsed.frontmatter["owner"] == "client-a"
    assert parsed.body == "Body by client b\n"
  end

  test "X-2 concurrent lock conflicts are deterministic and emit explicit conflict signaling" do
    root_dir = tmp_dir("x2")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "x2.md")
    File.write!(source_path, "---\ntitle: \"X2\"\npriority: 2\n---\nBody\n")

    registry_name = :"x2_registry_#{System.unique_integer([:positive])}"
    {:ok, registry} = SessionRegistry.start_link(name: registry_name)
    {:ok, session} = SessionRegistry.ensure_session_by_path(registry, source_path)

    assert :ok = SignalBus.subscribe(SignalBus, session.session_id)
    on_exit(fn -> SignalBus.unsubscribe(SignalBus, session.session_id) end)

    assert {:ok, _lock_a} = SessionRegistry.acquire_lock(registry, session.session_id, "client-a")

    assert_receive {:jido_document_signal,
                    %Signal{
                      session_id: session_id,
                      type: :updated,
                      data: %{action: :lock_state, payload: %{owner: "client-a"}}
                    }},
                   500

    assert session_id == session.session_id

    assert {:error, conflict} =
             SessionRegistry.acquire_lock(registry, session.session_id, "client-b")

    assert conflict.code == :conflict
    assert conflict.details.owner == "client-a"
    assert conflict.details.requested_owner == "client-b"

    assert {:ok, takeover} =
             SessionRegistry.force_takeover(registry, session.session_id, "client-b",
               reason: "deterministic override"
             )

    assert takeover.previous_owner == "client-a"

    assert_receive {:jido_document_signal,
                    %Signal{
                      session_id: ^session_id,
                      type: :updated,
                      data: %{
                        action: :lock_state,
                        payload: %{
                          action: :takeover,
                          owner: "client-b",
                          previous_owner: "client-a"
                        }
                      }
                    }},
                   500
  end

  test "X-3 render failures degrade gracefully while preserving last known good preview" do
    root_dir = tmp_dir("x3")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "x3.md")
    File.write!(source_path, "---\ntitle: \"X3\"\npriority: 3\n---\nRender body\n")

    session_id = "x3-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, agent} =
      Agent.start_link(
        session_id: session_id,
        render_circuit_threshold: 2,
        render_circuit_cooldown_ms: 100
      )

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
    end)

    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts("/"))

    first_render = Agent.command(agent, :render, %{})
    assert first_render.status == :ok
    last_good = first_render.value.preview

    fallback_render = Agent.command(agent, :render, %{render_opts: %{adapter: :unknown}})
    assert fallback_render.status == :ok
    assert fallback_render.metadata.fallback == true
    assert fallback_render.value.preview.metadata.fallback == true
    assert fallback_render.value.preview.toc == last_good.toc

    state = Agent.state(agent)
    assert state.last_good_preview == last_good
  end

  test "X-4 undo and redo remain coherent across frontmatter/body edits through save and reload" do
    root_dir = tmp_dir("x4")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "x4.md")
    File.write!(source_path, "---\ntitle: \"X4\"\npriority: 4\n---\nBody v1\n")

    session_id = "x4-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
    end)

    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts("/"))

    assert %{status: :ok} =
             Agent.command(agent, :update_frontmatter, %{changes: %{owner: "editor-a"}})

    assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "Body v2\n"})

    assert %{status: :ok, value: undo_value} = Agent.command(agent, :undo, %{})
    assert frontmatter_owner(undo_value.document.frontmatter) == "editor-a"
    assert undo_value.document.body == "Body v1\n"

    assert %{status: :ok, value: redo_value} = Agent.command(agent, :redo, %{})
    assert frontmatter_owner(redo_value.document.frontmatter) == "editor-a"
    assert redo_value.document.body == "Body v2\n"

    assert %{status: :ok} = Agent.command(agent, :save, %{path: source_path}, fs_opts("/"))

    reload_session = "x4-reload-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, reload_agent} = Agent.start_link(session_id: reload_session)

    on_exit(fn ->
      if Process.alive?(reload_agent), do: GenServer.stop(reload_agent, :normal)
    end)

    assert %{status: :ok, value: reloaded} =
             Agent.command(reload_agent, :load, %{path: source_path}, fs_opts("/"))

    assert frontmatter_owner(reloaded.document.frontmatter) == "editor-a"
    assert reloaded.document.body == "Body v2\n"
  end

  test "X-5 external file mutations are detected and save prevents silent overwrite" do
    root_dir = tmp_dir("x5")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "x5.md")
    File.write!(source_path, "---\ntitle: \"X5\"\npriority: 5\n---\nInitial\n")

    session_id = "x5-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
    end)

    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts("/"))
    assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "In-memory edit\n"})

    external = "---\ntitle: \"X5\"\npriority: 5\n---\nExternal writer\n"
    File.write!(source_path, external)

    assert %{status: :error, error: error} =
             Agent.command(agent, :save, %{path: source_path}, fs_opts("/"))

    assert error.code == :conflict
    assert File.read!(source_path) == external
  end

  test "X-6 unauthorized workspace/path access is rejected and audited" do
    root_dir = tmp_dir("x6")
    workspace_root = Path.join(root_dir, "workspace")
    File.mkdir_p!(workspace_root)
    on_exit(fn -> File.rm_rf(root_dir) end)

    outside_path = Path.join(root_dir, "outside.md")
    File.write!(outside_path, "---\ntitle: \"X6\"\npriority: 6\n---\nOutside\n")

    session_id = "x6-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
    end)

    assert %{status: :error, error: error} =
             Agent.command(agent, :load, %{path: outside_path}, fs_opts(workspace_root))

    assert error.code == :filesystem_error
    assert error.details.policy == :workspace_boundary

    trace = Agent.export_trace(agent, limit: 20)

    assert Enum.any?(trace.audit_events, fn event ->
             event.action == :load and event.status == :error and
               get_in(event, [:metadata, :error, :code]) == :filesystem_error
           end)
  end

  test "X-7 crash and restart during autosave/render recovers state without corruption" do
    root_dir = tmp_dir("x7")
    checkpoint_dir = Path.join(root_dir, "checkpoints")
    File.mkdir_p!(checkpoint_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(root_dir, "x7.md")
    File.write!(source_path, "---\ntitle: \"X7\"\npriority: 7\n---\nDisk baseline\n")

    session_id = "x7-" <> Integer.to_string(System.unique_integer([:positive]))

    opts = [
      session_id: session_id,
      checkpoint_dir: checkpoint_dir,
      checkpoint_on_edit: true,
      autosave_interval_ms: 20
    ]

    {:ok, agent} = Agent.start_link(opts)
    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts("/"))

    assert %{status: :ok} =
             Agent.command(agent, :update_body, %{body: "Unsaved checkpoint body\n"})

    assert %{status: :ok} = Agent.command(agent, :render, %{})

    Process.sleep(60)
    Process.unlink(agent)
    Process.exit(agent, :kill)
    Process.sleep(20)

    {:ok, restarted} = Agent.start_link(opts)

    on_exit(fn ->
      if Process.alive?(restarted), do: GenServer.stop(restarted, :normal)
    end)

    pending = Agent.recovery_status(restarted)
    assert pending != nil

    assert %{status: :ok, value: %{document: recovered_doc}} = Agent.recover(restarted)
    assert recovered_doc.body == "Unsaved checkpoint body\n"
    assert String.contains?(File.read!(source_path), "Disk baseline")
  end

  test "X-8 release artifacts, docs, and examples are reproducible from the same inputs" do
    root_dir = tmp_dir("x8")
    File.mkdir_p!(root_dir)
    on_exit(fn -> File.rm_rf(root_dir) end)

    changelog_a = Path.join(root_dir, "CHANGELOG_A.md")
    changelog_b = Path.join(root_dir, "CHANGELOG_B.md")
    notes_a = Path.join(root_dir, "RELEASE_A.md")
    notes_b = Path.join(root_dir, "RELEASE_B.md")

    {out1, status1} =
      run_mix([
        "jido.changelog",
        "--from",
        "HEAD~1",
        "--to",
        "HEAD",
        "--version",
        "CrossPhase",
        "--output",
        changelog_a
      ])

    {out2, status2} =
      run_mix([
        "jido.changelog",
        "--from",
        "HEAD~1",
        "--to",
        "HEAD",
        "--version",
        "CrossPhase",
        "--output",
        changelog_b
      ])

    assert status1 == 0
    assert status2 == 0
    assert out1 =~ "updated changelog"
    assert out2 =~ "updated changelog"
    assert File.read!(changelog_a) == File.read!(changelog_b)

    {notes_out1, notes_status1} =
      run_mix([
        "jido.release_notes",
        "--version",
        "CrossPhase",
        "--changelog",
        changelog_a,
        "--output",
        notes_a
      ])

    {notes_out2, notes_status2} =
      run_mix([
        "jido.release_notes",
        "--version",
        "CrossPhase",
        "--changelog",
        changelog_a,
        "--output",
        notes_b
      ])

    assert notes_status1 == 0
    assert notes_status2 == 0
    assert notes_out1 =~ "wrote release notes"
    assert notes_out2 =~ "wrote release notes"
    assert File.read!(notes_a) == File.read!(notes_b)

    docs = [
      "docs/public-api.md",
      "docs/quickstart.md",
      "docs/migration-guide.md",
      "docs/post-release-verification.md"
    ]

    for doc <- docs do
      assert File.regular?(Path.join(project_root(), doc))
    end

    {minimal_output, minimal_status} = run_mix(["run", "examples/minimal_api_sample.exs"])
    assert minimal_status == 0
    assert minimal_output =~ "session_id="
    assert minimal_output =~ "saved_bytes="
  end

  defp fs_opts(workspace_root) do
    [context_options: %{workspace_root: workspace_root}]
  end

  defp tmp_dir(prefix) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    Path.join(System.tmp_dir!(), "jido_document_cross_phase_#{prefix}_#{suffix}")
  end

  defp frontmatter_owner(frontmatter) when is_map(frontmatter) do
    Map.get(frontmatter, "owner") || Map.get(frontmatter, :owner)
  end

  defp run_mix(args) do
    System.cmd("mix", args,
      cd: project_root(),
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "test"}]
    )
  end

  defp project_root do
    Path.expand("../../..", __DIR__)
  end
end
