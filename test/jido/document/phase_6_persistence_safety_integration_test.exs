defmodule Jido.Document.Phase6PersistenceSafetyIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, PathPolicy}

  setup do
    session_id = "phase6-persistence-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase6_persistence_" <> session_id)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Phase 6\"\n---\nOriginal body\n")

    fs_opts = [context_options: %{workspace_root: "/"}]

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, tmp_dir: tmp_dir, source_path: source_path, fs_opts: fs_opts}
  end

  test "simulated save interruption leaves target file uncorrupted", ctx do
    path = Path.join(ctx.tmp_dir, "atomic.md")
    initial = "---\ntitle: \"Atomic\"\n---\nOriginal on disk\n"
    File.write!(path, initial)

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: path}, ctx.fs_opts)
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "In memory only\n"})

    result =
      Agent.command(
        ctx.agent,
        :save,
        %{path: path, atomic_write_opts: [inject_failure: :after_temp_write]},
        ctx.fs_opts
      )

    assert result.status == :error
    assert result.error.code == :filesystem_error
    assert File.read!(path) == initial
  end

  test "save blocks unsafe overwrite when file diverged on disk", ctx do
    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, ctx.fs_opts)
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Unsaved edits\n"})

    external = "---\ntitle: \"Phase 6\"\n---\nExternal writer won\n"
    File.write!(ctx.source_path, external)

    result = Agent.command(ctx.agent, :save, %{path: ctx.source_path}, ctx.fs_opts)
    {:ok, canonical_source_path} = PathPolicy.resolve_path(ctx.source_path, workspace_root: "/")

    assert result.status == :error
    assert result.error.code == :conflict
    assert result.error.details.path == canonical_source_path
    assert result.error.details.remediation == [:reload, :overwrite, :merge_hook]
    assert File.read!(ctx.source_path) == external
  end

  test "save preserves existing file mode metadata by default", ctx do
    path = Path.join(ctx.tmp_dir, "permissions.md")
    File.write!(path, "---\ntitle: \"Perms\"\n---\nBody\n")
    :ok = File.chmod(path, 0o640)
    original_mode = File.stat!(path).mode

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: path}, ctx.fs_opts)
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Updated\n"})
    assert %{status: :ok} = Agent.command(ctx.agent, :save, %{path: path}, ctx.fs_opts)

    assert File.stat!(path).mode == original_mode
    assert String.contains?(File.read!(path), "Updated")
  end
end
