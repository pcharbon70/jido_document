defmodule Mix.Tasks.Jido.Changelog do
  @moduledoc """
  Generates `CHANGELOG.md` entries from git commits.

      mix jido.changelog --from v0.1.0 --to HEAD
      mix jido.changelog --from HEAD~20 --to HEAD --output CHANGELOG.md
  """

  use Mix.Task

  @shortdoc "Generate changelog entries from git history"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [from: :string, to: :string, output: :string, version: :string]
      )

    from_ref = opts[:from] || last_tag_or_default()
    to_ref = opts[:to] || "HEAD"
    version = opts[:version] || "Unreleased"
    output = opts[:output] || "CHANGELOG.md"

    entries = git_log_entries(from_ref, to_ref)
    section = render_section(version, entries)
    content = merge_changelog(output, section)

    File.write!(output, content)
    Mix.shell().info("updated changelog: #{output}")
  end

  defp git_log_entries(from_ref, to_ref) do
    range = "#{from_ref}..#{to_ref}"

    case System.cmd("git", ["log", range, "--pretty=format:%h %s"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(fn line -> "- #{line}" end)

      {_output, _status} ->
        []
    end
  end

  defp render_section(version, entries) do
    body =
      case entries do
        [] -> "- No changes detected in selected range"
        list -> Enum.join(list, "\n")
      end

    """
    ## #{version}

    #{body}
    """
  end

  defp merge_changelog(path, new_section) do
    existing =
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> "# Changelog\n\n"
      end

    [header_line | _] = String.split(new_section, "\n", parts: 2)
    heading = String.trim(header_line)
    escaped_heading = Regex.escape(heading)
    regex = ~r/(#{escaped_heading}\n\n)(.*?)(\n## |\z)/ms

    if Regex.match?(regex, existing) do
      Regex.replace(regex, existing, fn _all, prefix, _existing_body, suffix ->
        prefix <> section_body(new_section) <> suffix
      end)
    else
      existing <> "\n" <> new_section <> "\n"
    end
  end

  defp section_body(section) do
    section
    |> String.split("\n", parts: 3)
    |> case do
      [_heading, _blank, body] -> body
      _ -> section
    end
  end

  defp last_tag_or_default do
    case System.cmd("git", ["describe", "--tags", "--abbrev=0"], stderr_to_stdout: true) do
      {tag, 0} -> String.trim(tag)
      {_output, _status} -> "HEAD~50"
    end
  end
end
