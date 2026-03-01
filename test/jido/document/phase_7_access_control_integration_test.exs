defmodule Jido.Document.Phase7AccessControlIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, PathPolicy, Signal}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    session_id = "phase7-access-" <> uniq

    {:ok, agent} = Agent.start_link(session_id: session_id)
    :ok = Agent.subscribe(agent)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase7_access_" <> uniq)
    workspace_root = Path.join(tmp_dir, "workspace")
    outside_root = Path.join(tmp_dir, "outside")

    File.mkdir_p!(workspace_root)
    File.mkdir_p!(outside_root)

    source_path = Path.join(workspace_root, "source.md")
    File.write!(source_path, "---\ntitle: \"Access\"\n---\nBody 0\n")
    File.mkdir_p!(Path.join(workspace_root, "docs"))

    outside_path = Path.join(outside_root, "outside.md")
    File.write!(outside_path, "---\ntitle: \"Outside\"\n---\nBody outside\n")

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    %{
      agent: agent,
      session_id: session_id,
      workspace_root: workspace_root,
      source_path: source_path,
      outside_path: outside_path
    }
  end

  test "canonicalizes in-workspace paths and blocks traversal/symlink escape", ctx do
    relative_path = Path.join(["docs", "..", "source.md"])

    assert %{status: :ok, value: load_value} =
             Agent.command(
               ctx.agent,
               :load,
               %{path: relative_path},
               context_options: %{workspace_root: ctx.workspace_root}
             )

    {:ok, canonical_source_path} =
      PathPolicy.resolve_path(relative_path, workspace_root: ctx.workspace_root)

    assert load_value.path == canonical_source_path

    assert %{status: :error, error: traversal_error} =
             Agent.command(
               ctx.agent,
               :load,
               %{path: "../outside/outside.md"},
               context_options: %{workspace_root: ctx.workspace_root}
             )

    assert traversal_error.code == :filesystem_error
    assert traversal_error.details.policy == :workspace_boundary

    symlink_path = Path.join(ctx.workspace_root, "escape_link.md")

    case File.ln_s(ctx.outside_path, symlink_path) do
      :ok ->
        assert %{status: :error, error: symlink_error} =
                 Agent.command(
                   ctx.agent,
                   :load,
                   %{path: "escape_link.md"},
                   context_options: %{workspace_root: ctx.workspace_root}
                 )

        assert symlink_error.code == :filesystem_error
        assert symlink_error.details.policy == :workspace_boundary

      {:error, _reason} ->
        :ok
    end
  end

  test "enforces action authorization matrix and emits deny events", ctx do
    policy = %{
      authorization: %{
        matrix: %{
          read: ["viewer", "editor", "admin"],
          write: ["editor", "admin"],
          admin: ["admin"]
        }
      },
      workspace_root: ctx.workspace_root
    }

    viewer = %{id: "viewer-1", roles: ["viewer"]}
    editor = %{id: "editor-1", roles: ["editor"]}

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :load,
               %{path: ctx.source_path},
               actor: viewer,
               context_options: policy
             )

    assert %{status: :error, error: denied} =
             Agent.command(
               ctx.agent,
               :update_body,
               %{body: "Viewer cannot write\n"},
               actor: viewer,
               context_options: policy
             )

    assert denied.code == :forbidden
    assert denied.details.required_permission == :write

    session_id = ctx.session_id

    assert_receive {:jido_document_signal,
                    %Signal{
                      type: :failed,
                      session_id: ^session_id,
                      data: %{action: :authorize, denied_action: :update_body, actor: actor}
                    }},
                   500

    assert actor.id == "viewer-1"

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :update_body,
               %{body: "Editor can write\n"},
               actor: editor,
               context_options: policy
             )
  end
end
