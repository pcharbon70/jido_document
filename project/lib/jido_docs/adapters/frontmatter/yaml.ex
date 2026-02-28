defmodule JidoDocs.Adapters.Frontmatter.Yaml do
  @moduledoc """
  YAML frontmatter adapter backed by `YamlElixir` when available.
  """

  @behaviour JidoDocs.Adapters.Frontmatter

  @impl true
  def parse(source) when is_binary(source) do
    cond do
      Code.ensure_loaded?(YamlElixir) and function_exported?(YamlElixir, :read_from_string, 1) ->
        case apply(YamlElixir, :read_from_string, [source]) do
          {:ok, map} when is_map(map) -> {:ok, map}
          map when is_map(map) -> {:ok, map}
          other -> {:error, {:yaml_parse_failed, other}}
        end

      true ->
        {:error, :yaml_parser_unavailable}
    end
  end

  @impl true
  def serialize(frontmatter) when is_map(frontmatter) do
    cond do
      Code.ensure_loaded?(YamlElixir) and function_exported?(YamlElixir, :write_to_string, 1) ->
        case apply(YamlElixir, :write_to_string, [frontmatter]) do
          {:ok, yaml} when is_binary(yaml) -> {:ok, yaml}
          yaml when is_binary(yaml) -> {:ok, yaml}
          other -> {:error, {:yaml_serialize_failed, other}}
        end

      true ->
        {:error, :yaml_parser_unavailable}
    end
  end
end
