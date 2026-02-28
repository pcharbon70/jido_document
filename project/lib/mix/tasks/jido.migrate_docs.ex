defmodule Mix.Tasks.Jido.MigrateDocs do
  @moduledoc """
  Migrates legacy markdown/frontmatter directories to the canonical model.

      mix jido.migrate_docs --source ./content
      mix jido.migrate_docs --source ./content --apply --backup-dir ./migration_backups
      mix jido.migrate_docs --source ./content --template blog_frontmatter --apply
      mix jido.migrate_docs --source ./content --mapping ./priv/migration/custom_mapping.exs --apply
      mix jido.migrate_docs --list-templates
  """

  use Mix.Task

  alias Jido.Document.{Error, Migrator}

  @shortdoc "Normalize a directory of markdown/frontmatter documents"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          source: :string,
          apply: :boolean,
          mapping: :string,
          template: :string,
          backup_dir: :string,
          allow_destructive: :boolean,
          include_glob: :string,
          syntax: :string,
          line_endings: :string,
          emit_empty_frontmatter: :boolean,
          report: :string,
          list_templates: :boolean
        ]
      )

    if opts[:list_templates] do
      print_templates()
    else
      source = opts[:source] || "."

      migrate_opts = [
        apply: opts[:apply] || false,
        mapping: opts[:mapping],
        template: opts[:template],
        backup_dir: opts[:backup_dir],
        allow_destructive: opts[:allow_destructive] || false,
        include_glob: opts[:include_glob] || "**/*.{md,markdown}",
        syntax: opts[:syntax],
        line_endings: opts[:line_endings] || "lf",
        emit_empty_frontmatter: opts[:emit_empty_frontmatter] || false
      ]

      case Migrator.migrate_directory(source, migrate_opts) do
        {:ok, report} ->
          maybe_write_report(opts[:report], report)
          print_summary(report)
          maybe_print_failures(report)
          fail_if_errors(report)

        {:error, %Error{} = error} ->
          Mix.raise(format_error(error))
      end
    end
  end

  defp print_templates do
    names = Migrator.template_names()

    if names == [] do
      Mix.shell().info("No migration templates found.")
    else
      Mix.shell().info("Available migration templates:")
      Enum.each(names, fn name -> Mix.shell().info("  - " <> name) end)
    end
  end

  defp maybe_write_report(nil, _report), do: :ok

  defp maybe_write_report(path, report) do
    case Migrator.write_report(report, path) do
      :ok ->
        Mix.shell().info("wrote migration report: #{path}")

      {:error, %Error{} = error} ->
        Mix.raise(format_error(error))
    end
  end

  defp print_summary(report) do
    mode = if report.dry_run, do: "dry-run", else: "apply"

    Mix.shell().info("migration mode: #{mode}")
    Mix.shell().info("source_dir: #{report.source_dir}")
    Mix.shell().info("include_glob: #{report.include_glob}")
    Mix.shell().info("total_files: #{report.total_files}")
    Mix.shell().info("changed_files: #{report.changed_files}")
    Mix.shell().info("written_files: #{report.written_files}")
    Mix.shell().info("failed_files: #{report.failed_files}")
  end

  defp maybe_print_failures(report) do
    report.entries
    |> Enum.filter(&(&1.status == :error))
    |> Enum.each(fn entry ->
      Mix.shell().error(
        "migration failed for #{entry.relative_path}: #{format_error(entry.error)}"
      )
    end)
  end

  defp fail_if_errors(%{failed_files: failed_files}) when failed_files > 0 do
    Mix.raise("migration finished with #{failed_files} failed file(s)")
  end

  defp fail_if_errors(_report), do: :ok

  defp format_error(%Error{} = error) do
    "#{error.message} (code=#{error.code}, details=#{inspect(error.details)})"
  end
end
