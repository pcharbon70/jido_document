defmodule Jido.Document.Phase8MigrationRoadmapIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.Migrator

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    root_dir = Path.join(System.tmp_dir!(), "jido_document_phase8_migration_" <> uniq)
    source_dir = Path.join(root_dir, "source")
    backup_dir = Path.join(root_dir, "backup")

    File.mkdir_p!(source_dir)

    source_path = Path.join(source_dir, "legacy.md")

    raw = """
    ---
    headline: "Legacy title"
    draft: "true"
    priority: "2"
    legacy_key: "remove-me"
    ---
    Legacy body
    """

    File.write!(source_path, raw)

    on_exit(fn -> File.rm_rf(root_dir) end)

    %{
      root_dir: root_dir,
      source_dir: source_dir,
      backup_dir: backup_dir,
      source_path: source_path,
      raw: raw
    }
  end

  test "dry-run reports changes without mutating source files", ctx do
    {:ok, report} =
      Migrator.migrate_directory(ctx.source_dir,
        mapping: custom_mapping_path(ctx.root_dir),
        apply: false
      )

    assert report.dry_run
    assert report.total_files == 1
    assert report.changed_files == 1
    assert report.written_files == 0
    assert report.failed_files == 0

    [entry] = report.entries
    assert entry.status == :ok
    assert entry.changed
    refute entry.written

    assert File.read!(ctx.source_path) == ctx.raw
  end

  test "apply mode writes canonical output and backups", ctx do
    {:ok, report} =
      Migrator.migrate_directory(ctx.source_dir,
        mapping: custom_mapping_path(ctx.root_dir),
        apply: true,
        allow_destructive: true,
        backup_dir: ctx.backup_dir
      )

    assert report.dry_run == false
    assert report.total_files == 1
    assert report.changed_files == 1
    assert report.written_files == 1
    assert report.failed_files == 0

    backup_path = Path.join(ctx.backup_dir, "legacy.md")
    assert File.read!(backup_path) == ctx.raw

    migrated = File.read!(ctx.source_path)

    assert String.contains?(migrated, "title: \"Legacy title\"")
    assert String.contains?(migrated, "draft: true")
    assert String.contains?(migrated, "priority: 2")
    assert String.contains?(migrated, "status: \"draft\"")
    refute String.contains?(migrated, "legacy_key")
  end

  test "bundled templates can be listed and report files can be written", ctx do
    assert "blog_frontmatter" in Migrator.template_names()
    assert "knowledge_base" in Migrator.template_names()
    assert {:ok, template} = Migrator.load_template("blog_frontmatter")
    assert is_map(template.rename)
    assert is_map(template.defaults)

    {:ok, report} =
      Migrator.migrate_directory(ctx.source_dir,
        template: "blog_frontmatter",
        apply: false
      )

    report_path = Path.join(ctx.root_dir, "migration_report.exs")
    assert :ok = Migrator.write_report(report, report_path)
    assert File.regular?(report_path)

    {saved_report, _binding} = Code.eval_file(report_path)
    assert saved_report.total_files == report.total_files
    assert saved_report.changed_files == report.changed_files
  end

  defp custom_mapping_path(root_dir) do
    path = Path.join(root_dir, "custom_mapping.exs")

    content = """
    %{
      rename: %{"headline" => "title"},
      coerce: %{"draft" => :boolean, "priority" => :integer},
      drop: ["legacy_key"],
      defaults: %{"status" => "draft"}
    }
    """

    File.write!(path, content)
    path
  end
end
