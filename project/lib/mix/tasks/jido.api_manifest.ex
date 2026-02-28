defmodule Mix.Tasks.Jido.ApiManifest do
  @moduledoc """
  Writes or validates the stable public API manifest.

      mix jido.api_manifest
      mix jido.api_manifest --check
      mix jido.api_manifest --output priv/api/public_api_manifest.exs
  """

  use Mix.Task

  alias Jido.Document.PublicApi

  @shortdoc "Write or check public API manifest"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [check: :boolean, output: :string])

    output_path = opts[:output] || PublicApi.default_manifest_path()

    case PublicApi.validate_contract() do
      :ok ->
        :ok

      {:error, details} ->
        Mix.raise("invalid public API contract: #{inspect(details, pretty: true)}")
    end

    if opts[:check] do
      check_manifest(output_path)
    else
      case PublicApi.write_manifest(output_path) do
        :ok ->
          Mix.shell().info("wrote API manifest: #{output_path}")

        {:error, reason} ->
          Mix.raise("failed to write API manifest: #{inspect(reason)}")
      end
    end
  end

  defp check_manifest(path) do
    expected = PublicApi.manifest_without_timestamp()

    case PublicApi.read_manifest(path) do
      {:ok, ^expected} ->
        Mix.shell().info("API manifest matches: #{path}")

      {:ok, existing} ->
        Mix.shell().error("API manifest drift detected at: #{path}")
        Mix.shell().error("Expected:\n#{inspect(expected, pretty: true, limit: :infinity)}")
        Mix.shell().error("Actual:\n#{inspect(existing, pretty: true, limit: :infinity)}")
        Mix.raise("public API manifest mismatch")

      {:error, reason} ->
        Mix.raise("failed to read API manifest: #{inspect(reason)}")
    end
  end
end
