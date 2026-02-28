defmodule Jido.Document.Phase6RevisionSchemaIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, SchemaMigration}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    session_id = "phase6-revision-" <> uniq

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase6_revision_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Revision\"\n---\nBody 0\n")

    {:ok, agent} = Agent.start_link(session_id: session_id)

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, session_id: session_id, source_path: source_path}
  end

  test "save persists monotonic revision sidecar metadata", ctx do
    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, fs_opts())
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Body 1\n"})
    assert %{status: :ok} = Agent.command(ctx.agent, :save, %{path: ctx.source_path}, fs_opts())

    sidecar_path = ctx.source_path <> ".jido.rev"
    metadata1 = read_sidecar!(sidecar_path)

    assert metadata1.session_id == ctx.session_id
    assert metadata1.action == :save
    assert metadata1.source == "agent"
    assert metadata1.actor == "session:" <> ctx.session_id
    assert metadata1.document_revision == Agent.state(ctx.agent).document.revision

    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Body 2\n"})
    assert %{status: :ok} = Agent.command(ctx.agent, :save, %{path: ctx.source_path}, fs_opts())

    metadata2 = read_sidecar!(sidecar_path)
    assert metadata2.sequence > metadata1.sequence
    assert metadata2.revision_id != metadata1.revision_id
    assert String.starts_with?(metadata2.revision_id, ctx.session_id <> "-")
  end

  test "schema migration helpers support dry-run and destructive guards" do
    frontmatter = %{"title" => "My Doc", "count" => "42", "legacy" => "remove-me"}

    non_destructive_ops = [
      {:rename, "title", "name"},
      {:coerce, "count", :integer}
    ]

    assert {:ok, dry_run} = SchemaMigration.dry_run(frontmatter, non_destructive_ops)
    assert dry_run.dry_run == true
    assert dry_run.frontmatter["name"] == "My Doc"
    assert dry_run.frontmatter["count"] == 42
    assert dry_run.frontmatter["legacy"] == "remove-me"

    destructive_ops = non_destructive_ops ++ [{:drop, "legacy"}]

    assert {:error, guarded} = SchemaMigration.apply(frontmatter, destructive_ops)
    assert guarded.code == :validation_failed

    assert {:ok, migrated} =
             SchemaMigration.apply(frontmatter, destructive_ops, allow_destructive: true)

    assert migrated.dry_run == false
    assert migrated.frontmatter["name"] == "My Doc"
    assert migrated.frontmatter["count"] == 42
    refute Map.has_key?(migrated.frontmatter, "legacy")
  end

  defp read_sidecar!(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term()
  end

  defp fs_opts, do: [context_options: %{workspace_root: "/"}]
end
