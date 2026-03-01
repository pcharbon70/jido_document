defmodule Jido.Document.Frontmatter do
  @moduledoc """
  Frontmatter split/parse/serialize helpers for YAML (`---`) and TOML (`+++`).
  """

  @type syntax :: :yaml | :toml

  @type split_result :: %{
          frontmatter: String.t() | nil,
          body: String.t(),
          syntax: syntax() | nil
        }

  @type validation_error :: %{
          path: [atom() | String.t()],
          message: String.t(),
          value: term()
        }

  @yaml_delimiter "---"
  @toml_delimiter "+++"

  @spec split(String.t()) :: {:ok, split_result()} | {:error, validation_error()}
  def split(raw) when is_binary(raw) do
    cond do
      String.starts_with?(raw, @yaml_delimiter <> "\n") ->
        split_with_delimiter(raw, :yaml, @yaml_delimiter)

      String.starts_with?(raw, @toml_delimiter <> "\n") ->
        split_with_delimiter(raw, :toml, @toml_delimiter)

      true ->
        {:ok, %{frontmatter: nil, body: raw, syntax: nil}}
    end
  end

  @spec parse(String.t() | nil, syntax() | nil) :: {:ok, map()} | {:error, validation_error()}
  def parse(nil, _syntax), do: {:ok, %{}}

  def parse(frontmatter_source, nil), do: parse(frontmatter_source, :yaml)

  def parse(frontmatter_source, :yaml) when is_binary(frontmatter_source) do
    cond do
      Code.ensure_loaded?(YamlElixir) and function_exported?(YamlElixir, :read_from_string, 1) ->
        case apply(YamlElixir, :read_from_string, [frontmatter_source]) do
          {:ok, map} when is_map(map) -> {:ok, map}
          map when is_map(map) -> {:ok, map}
          other -> {:error, error([:frontmatter], "failed to parse YAML frontmatter", other)}
        end

      true ->
        parse_yaml_fallback(frontmatter_source)
    end
  end

  def parse(frontmatter_source, :toml) when is_binary(frontmatter_source) do
    cond do
      Code.ensure_loaded?(Toml) and function_exported?(Toml, :decode, 1) ->
        case apply(Toml, :decode, [frontmatter_source]) do
          {:ok, map} when is_map(map) -> {:ok, map}
          map when is_map(map) -> {:ok, map}
          other -> {:error, error([:frontmatter], "failed to parse TOML frontmatter", other)}
        end

      true ->
        parse_toml_fallback(frontmatter_source)
    end
  end

  @spec serialize(map(), syntax() | nil) :: {:ok, String.t()} | {:error, validation_error()}
  def serialize(frontmatter, _syntax) when not is_map(frontmatter) do
    {:error, error([:frontmatter], "must be a map", frontmatter)}
  end

  def serialize(frontmatter, nil), do: serialize(frontmatter, :yaml)

  def serialize(frontmatter, :yaml) do
    encoded =
      frontmatter
      |> sorted_entries()
      |> Enum.map_join("\n", fn {key, value} ->
        "#{key}: #{encode_scalar(value)}"
      end)

    {:ok, encoded}
  end

  def serialize(frontmatter, :toml) do
    encoded =
      frontmatter
      |> sorted_entries()
      |> Enum.map_join("\n", fn {key, value} ->
        "#{key} = #{encode_scalar(value)}"
      end)

    {:ok, encoded}
  end

  @spec delimiter_for(syntax()) :: String.t()
  def delimiter_for(:yaml), do: @yaml_delimiter
  def delimiter_for(:toml), do: @toml_delimiter

  defp split_with_delimiter(raw, syntax, delimiter) do
    source = String.split(raw, "\n")

    case find_closing_delimiter(source, delimiter, 1) do
      {:ok, closing_index} ->
        fm_lines = Enum.slice(source, 1, closing_index - 1)
        body_lines = Enum.slice(source, (closing_index + 1)..-1//1)

        {:ok,
         %{
           frontmatter: Enum.join(fm_lines, "\n"),
           body: Enum.join(body_lines, "\n"),
           syntax: syntax
         }}

      :error ->
        {:error,
         error(
           [:frontmatter],
           "missing closing #{delimiter} delimiter",
           %{line: 1, syntax: syntax}
         )}
    end
  end

  defp find_closing_delimiter(lines, delimiter, index) do
    case Enum.at(lines, index) do
      nil ->
        :error

      ^delimiter ->
        {:ok, index}

      _ ->
        find_closing_delimiter(lines, delimiter, index + 1)
    end
  end

  defp parse_yaml_fallback(source) do
    parse_key_value_lines(source, ":")
  end

  defp parse_toml_fallback(source) do
    parse_key_value_lines(source, "=")
  end

  defp parse_key_value_lines(source, separator) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}}, fn {line, line_number}, {:ok, acc} ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" or String.starts_with?(trimmed, "#") ->
          {:cont, {:ok, acc}}

        not String.contains?(trimmed, separator) ->
          {:halt,
           {:error,
            error(
              [:frontmatter],
              "invalid frontmatter line format",
              %{line: line_number, line_text: line}
            )}}

        true ->
          [raw_key, raw_value] = String.split(trimmed, separator, parts: 2)
          key = String.trim(raw_key)
          value = String.trim(raw_value)

          if key == "" do
            {:halt,
             {:error,
              error(
                [:frontmatter],
                "frontmatter key cannot be empty",
                %{line: line_number, line_text: line}
              )}}
          else
            {:cont, {:ok, Map.put(acc, key, decode_scalar(value))}}
          end
      end
    end)
  end

  defp sorted_entries(frontmatter) do
    frontmatter
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp decode_scalar(value) do
    cond do
      value in ["true", "false"] ->
        value == "true"

      Regex.match?(~r/^[-+]?\d+$/, value) ->
        String.to_integer(value)

      Regex.match?(~r/^[-+]?\d+\.\d+$/, value) ->
        String.to_float(value)

      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        value |> String.trim_leading("\"") |> String.trim_trailing("\"")

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        value |> String.trim_leading("'") |> String.trim_trailing("'")

      true ->
        value
    end
  end

  defp encode_scalar(value) when is_binary(value) do
    ~s("#{String.replace(value, "\"", "\\\"")}")
  end

  defp encode_scalar(value) when is_boolean(value), do: to_string(value)
  defp encode_scalar(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_scalar(value) when is_float(value), do: Float.to_string(value)

  defp encode_scalar(value) when is_list(value) do
    values = Enum.map_join(value, ", ", &encode_scalar/1)
    "[#{values}]"
  end

  defp encode_scalar(value), do: inspect(value)

  defp error(path, message, value) do
    %{path: path, message: message, value: value}
  end
end
