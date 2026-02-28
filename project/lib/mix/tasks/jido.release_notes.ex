defmodule Mix.Tasks.Jido.ReleaseNotes do
  @moduledoc """
  Generates release notes markdown from changelog and API manifest status.

      mix jido.release_notes --version 0.2.0
      mix jido.release_notes --version 0.2.0 --output RELEASE_NOTES.md
  """

  use Mix.Task

  alias Jido.Document.PublicApi

  @shortdoc "Generate release notes"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [version: :string, output: :string, changelog: :string])

    version = opts[:version] || "Unreleased"
    output = opts[:output] || "RELEASE_NOTES.md"
    changelog_path = opts[:changelog] || "CHANGELOG.md"

    api_status =
      case PublicApi.validate_contract() do
        :ok -> "API snapshot is consistent with stable contract."
        {:error, details} -> "API contract drift detected: #{inspect(details)}"
      end

    changelog_excerpt = changelog_excerpt(changelog_path, version)

    notes = """
    # Release Notes #{version}

    ## API Contract
    #{api_status}

    ## Changelog Summary
    #{changelog_excerpt}

    ## Release Gates
    - mix ci
    - mix jido.api_manifest --check
    - mix test
    """

    File.write!(output, notes)
    Mix.shell().info("wrote release notes: #{output}")
  end

  defp changelog_excerpt(path, version) do
    case File.read(path) do
      {:ok, content} ->
        case String.split(content, "## #{version}", parts: 2) do
          [_prefix, suffix] ->
            "## #{version}" <>
              (suffix |> String.split("\n## ", parts: 2) |> hd())

          _ ->
            "No matching changelog section found for #{version}."
        end

      {:error, _} ->
        "Changelog not found."
    end
  end
end
