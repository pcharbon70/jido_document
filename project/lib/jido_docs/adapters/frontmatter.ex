defmodule JidoDocs.Adapters.Frontmatter do
  @moduledoc """
  Frontmatter parsing and serialization adapter boundary.
  """

  alias JidoDocs.Error

  @type syntax :: :yaml | :toml

  @callback parse(String.t()) :: {:ok, map()} | {:error, term()}
  @callback serialize(map()) :: {:ok, String.t()} | {:error, term()}

  @spec parse(syntax(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def parse(syntax, source, opts \\ []) do
    adapter = adapter_for(syntax, opts)

    case adapter.parse(source) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        Error.wrap(:invalid_input, :frontmatter_parser_returned_non_map, %{value: other})

      {:error, reason} ->
        Error.wrap(:parser_unavailable, reason, %{adapter: adapter, syntax: syntax})

      other ->
        Error.wrap(:upstream_error, :unexpected_frontmatter_parser_response, %{
          adapter: adapter,
          response: other
        })
    end
  end

  @spec serialize(syntax(), map(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def serialize(syntax, frontmatter, opts \\ []) do
    adapter = adapter_for(syntax, opts)

    case adapter.serialize(frontmatter) do
      {:ok, serialized} when is_binary(serialized) ->
        {:ok, serialized}

      {:ok, other} ->
        Error.wrap(:invalid_input, :frontmatter_serializer_returned_non_binary, %{value: other})

      {:error, reason} ->
        Error.wrap(:parser_unavailable, reason, %{adapter: adapter, syntax: syntax})

      other ->
        Error.wrap(:upstream_error, :unexpected_frontmatter_serializer_response, %{
          adapter: adapter,
          response: other
        })
    end
  end

  defp adapter_for(:yaml, opts) do
    Keyword.get(opts, :yaml_adapter, JidoDocs.Adapters.Frontmatter.Yaml)
  end

  defp adapter_for(:toml, opts) do
    Keyword.get(opts, :toml_adapter, JidoDocs.Adapters.Frontmatter.Toml)
  end
end
