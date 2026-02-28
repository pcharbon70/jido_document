defmodule Jido.Document.Phase8ReleaseReadinessIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, Migrator, Persistence, PublicApi}

  test "executes canary validation on representative workloads before broad release" do
    root_dir = tmp_dir("phase8_canary")
    File.mkdir_p!(root_dir)

    on_exit(fn -> File.rm_rf(root_dir) end)

    document_paths =
      for index <- 1..6 do
        path = Path.join(root_dir, "canary_#{index}.md")
        File.write!(path, "---\ntitle: \"Canary #{index}\"\n---\nBody #{index}\n")
        {index, path}
      end

    started_ms = System.monotonic_time(:millisecond)

    failures =
      Enum.flat_map(document_paths, fn {index, path} ->
        session_id = "phase8-canary-#{index}-#{System.unique_integer([:positive])}"
        {:ok, agent} = Agent.start_link(session_id: session_id)

        results =
          [
            Agent.command(agent, :load, %{path: path}, fs_opts()),
            Agent.command(agent, :update_body, %{body: "Canary body #{index}\n"}),
            Agent.command(agent, :render, %{}),
            Agent.command(agent, :save, %{path: path}, fs_opts())
          ]

        if Process.alive?(agent), do: GenServer.stop(agent, :normal)

        case Enum.find(results, &(&1.status == :error)) do
          nil ->
            []

          error_result ->
            [%{path: path, error: error_result.error, session_id: session_id}]
        end
      end)

    duration_ms = System.monotonic_time(:millisecond) - started_ms

    assert failures == []
    assert duration_ms < 15_000

    for {index, path} <- document_paths do
      assert String.contains?(File.read!(path), "Canary body #{index}")
    end
  end

  test "executes rollback rehearsal by restoring backups after migration apply" do
    root_dir = tmp_dir("phase8_rollback")
    source_dir = Path.join(root_dir, "source")
    backup_dir = Path.join(root_dir, "backup")
    File.mkdir_p!(source_dir)

    on_exit(fn -> File.rm_rf(root_dir) end)

    source_path = Path.join(source_dir, "legacy.md")

    original = """
    ---
    headline: "Rollback title"
    draft: "true"
    old_field: "deprecated"
    ---
    Rollback body
    """

    File.write!(source_path, original)
    mapping_path = write_mapping_file(root_dir)

    {:ok, report} =
      Migrator.migrate_directory(source_dir,
        mapping: mapping_path,
        apply: true,
        allow_destructive: true,
        backup_dir: backup_dir
      )

    assert report.failed_files == 0
    assert report.changed_files == 1
    assert report.written_files == 1

    migrated = File.read!(source_path)
    refute migrated == original

    backup_path = Path.join(backup_dir, "legacy.md")
    restored = File.read!(backup_path)
    assert restored == original
    assert {:ok, _snapshot} = Persistence.atomic_write(source_path, restored)
    assert File.read!(source_path) == original
  end

  test "verifies migration outputs are reproducible across equivalent environments" do
    root_dir = tmp_dir("phase8_repro")
    env_a = Path.join(root_dir, "env_a")
    env_b = Path.join(root_dir, "env_b")
    File.mkdir_p!(Path.join(env_a, "nested"))
    File.mkdir_p!(Path.join(env_b, "nested"))

    on_exit(fn -> File.rm_rf(root_dir) end)

    docs = [
      {"doc_one.md", "---\nheadline: \"One\"\ndraft: \"false\"\n---\nOne\n"},
      {"nested/doc_two.md", "---\nheadline: \"Two\"\npriority: \"9\"\n---\nTwo\n"}
    ]

    Enum.each(docs, fn {relative, raw} ->
      File.write!(Path.join(env_a, relative), raw)
      File.write!(Path.join(env_b, relative), raw)
    end)

    mapping_path = write_mapping_file(root_dir)

    opts = [
      mapping: mapping_path,
      apply: true,
      allow_destructive: true
    ]

    {:ok, report_a} = Migrator.migrate_directory(env_a, opts)
    {:ok, report_b} = Migrator.migrate_directory(env_b, opts)

    assert report_a.failed_files == 0
    assert report_b.failed_files == 0
    assert report_a.changed_files == report_b.changed_files

    Enum.each(docs, fn {relative, _raw} ->
      assert File.read!(Path.join(env_a, relative)) == File.read!(Path.join(env_b, relative))
    end)

    assert PublicApi.manifest_without_timestamp() == PublicApi.manifest_without_timestamp()
  end

  defp fs_opts, do: [context_options: %{workspace_root: "/"}]

  defp tmp_dir(prefix) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    Path.join(System.tmp_dir!(), "jido_document_#{prefix}_#{suffix}")
  end

  defp write_mapping_file(root_dir) do
    path = Path.join(root_dir, "mapping.exs")

    content = """
    %{
      rename: %{"headline" => "title"},
      coerce: %{"draft" => :boolean, "priority" => :integer},
      drop: ["old_field"],
      defaults: %{"status" => "ready"}
    }
    """

    File.write!(path, content)
    path
  end
end
