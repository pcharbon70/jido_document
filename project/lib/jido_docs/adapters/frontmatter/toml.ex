defmodule JidoDocs.Adapters.Frontmatter.Toml do
  @moduledoc """
  TOML frontmatter adapter backed by `Toml` when available.
  """

  @behaviour JidoDocs.Adapters.Frontmatter

  @impl true
  def parse(source) when is_binary(source) do
    cond do
      Code.ensure_loaded?(Toml) and function_exported?(Toml, :decode, 1) ->
        case apply(Toml, :decode, [source]) do
          {:ok, map} when is_map(map) -> {:ok, map}
          map when is_map(map) -> {:ok, map}
          other -> {:error, {:toml_parse_failed, other}}
        end

      true ->
        {:error, :toml_parser_unavailable}
    end
  end

  @impl true
  def serialize(frontmatter) when is_map(frontmatter) do
    cond do
      Code.ensure_loaded?(Toml) and function_exported?(Toml, :encode, 1) ->
        case apply(Toml, :encode, [frontmatter]) do
          {:ok, toml} when is_binary(toml) -> {:ok, toml}
          toml when is_binary(toml) -> {:ok, toml}
          other -> {:error, {:toml_serialize_failed, other}}
        end

      true ->
        {:error, :toml_parser_unavailable}
    end
  end
end
