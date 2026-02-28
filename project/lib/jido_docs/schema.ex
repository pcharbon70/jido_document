defmodule JidoDocs.Schema do
  @moduledoc """
  Schema behavior contract and validation engine for frontmatter maps.
  """

  alias JidoDocs.Field

  @type unknown_keys_policy :: :warn | :ignore | :reject

  @type validation_error :: %{
          path: [atom() | String.t()],
          message: String.t(),
          value: term()
        }

  @type warning :: validation_error()

  @callback fields() :: [Field.t()]

  @spec validate_frontmatter(map(), module(), keyword()) ::
          {:ok, map(), [warning()]} | {:error, [validation_error()]}
  def validate_frontmatter(frontmatter, schema, opts \\ [])

  def validate_frontmatter(frontmatter, schema, opts)
      when is_map(frontmatter) and is_atom(schema) do
    with {:ok, fields} <- fetch_fields(schema) do
      unknown_policy = Keyword.get(opts, :unknown_keys, :warn)
      coerce? = Keyword.get(opts, :coerce, true)

      {normalized, errors} = validate_fields(frontmatter, fields, coerce?)
      {unknown_errors, warnings} = handle_unknown_keys(frontmatter, fields, unknown_policy)

      all_errors = errors ++ unknown_errors

      case all_errors do
        [] -> {:ok, normalized, warnings}
        _ -> {:error, all_errors}
      end
    end
  end

  def validate_frontmatter(frontmatter, _schema, _opts) do
    {:error, [%{path: [:frontmatter], message: "must be a map", value: frontmatter}]}
  end

  @spec field_names(module()) :: {:ok, [atom()]} | {:error, [validation_error()]}
  def field_names(schema) when is_atom(schema) do
    with {:ok, fields} <- fetch_fields(schema) do
      {:ok, Enum.map(fields, & &1.name)}
    end
  end

  defp fetch_fields(schema) do
    cond do
      not Code.ensure_loaded?(schema) ->
        {:error, [%{path: [:schema], message: "schema module is not available", value: schema}]}

      not function_exported?(schema, :fields, 0) ->
        {:error, [%{path: [:schema], message: "schema must export fields/0", value: schema}]}

      true ->
        fields = schema.fields()

        case normalize_fields(fields) do
          {:ok, normalized} -> {:ok, normalized}
          {:error, errors} -> {:error, errors}
        end
    end
  end

  defp normalize_fields(fields) when is_list(fields) do
    fields
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {field, index}, {acc, errors} ->
      case normalize_field(field, index) do
        {:ok, normalized} -> {[normalized | acc], errors}
        {:error, error} -> {acc, [error | errors]}
      end
    end)
    |> then(fn {fields_acc, errors} ->
      case errors do
        [] -> {:ok, Enum.reverse(fields_acc)}
        _ -> {:error, Enum.reverse(errors)}
      end
    end)
  end

  defp normalize_fields(fields) do
    {:error, [%{path: [:schema, :fields], message: "must return a list", value: fields}]}
  end

  defp normalize_field(%Field{name: name} = field, _index) when is_atom(name) do
    {:ok, %{field | label: field.label || pretty_label(name)}}
  end

  defp normalize_field(%{} = field_map, index) do
    name = Map.get(field_map, :name)

    if is_atom(name) do
      {:ok, struct(Field, field_map |> Map.put_new(:label, pretty_label(name)))}
    else
      {:error, %{path: [:schema, :fields, index, :name], message: "must be an atom", value: name}}
    end
  end

  defp normalize_field(other, index) do
    {:error,
     %{path: [:schema, :fields, index], message: "invalid field declaration", value: other}}
  end

  defp validate_fields(frontmatter, fields, coerce?) do
    Enum.reduce(fields, {%{}, []}, fn field, {normalized, errors} ->
      key = field.name
      value = Map.get(frontmatter, key, Map.get(frontmatter, Atom.to_string(key), :__missing__))

      cond do
        value == :__missing__ and not is_nil(field.default) ->
          {Map.put(normalized, key, field.default), errors}

        value == :__missing__ and field.required ->
          {normalized, [field_error(field, "is required", :missing) | errors]}

        value == :__missing__ ->
          {normalized, errors}

        true ->
          case cast_value(value, field.type, coerce?) do
            {:ok, casted} ->
              case run_custom_validator(field, casted) do
                :ok -> {Map.put(normalized, key, casted), errors}
                {:error, message} -> {normalized, [field_error(field, message, casted) | errors]}
              end

            {:error, message} ->
              {normalized, [field_error(field, message, value) | errors]}
          end
      end
    end)
    |> then(fn {normalized, errors} -> {normalized, Enum.reverse(errors)} end)
  end

  defp run_custom_validator(%Field{validator: nil}, _value), do: :ok

  defp run_custom_validator(%Field{validator: validator}, value) when is_function(validator, 1) do
    case validator.(value) do
      :ok -> :ok
      true -> :ok
      false -> {:error, "failed custom validator"}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> {:error, "invalid custom validator return: #{inspect(other)}"}
    end
  end

  defp run_custom_validator(_field, _value), do: {:error, "validator must be a unary function"}

  defp handle_unknown_keys(frontmatter, fields, policy) do
    known_keys =
      fields
      |> Enum.map(&Atom.to_string(&1.name))
      |> MapSet.new()

    unknown_entries =
      frontmatter
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.filter(fn {key, _value} -> not MapSet.member?(known_keys, key) end)

    case policy do
      :ignore ->
        {[], []}

      :warn ->
        {[],
         Enum.map(unknown_entries, fn {key, value} ->
           %{path: [:frontmatter, :unknown_key], message: "unknown key: #{key}", value: value}
         end)}

      :reject ->
        {Enum.map(unknown_entries, fn {key, value} ->
           %{path: [:frontmatter, :unknown_key], message: "unknown key: #{key}", value: value}
         end), []}

      other ->
        {[%{path: [:unknown_keys], message: "invalid unknown key policy", value: other}], []}
    end
  end

  defp cast_value(value, type, _coerce?) when type in [:string, :integer, :float, :boolean] do
    cast_primitive(value, type)
  end

  defp cast_value(value, {:array, subtype}, coerce?) do
    list_value =
      cond do
        is_list(value) -> {:ok, value}
        coerce? and is_binary(value) -> {:ok, split_csv(value)}
        true -> {:error, "must be a list"}
      end

    with {:ok, values} <- list_value do
      values
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
        case cast_primitive(entry, subtype) do
          {:ok, casted} -> {:cont, {:ok, [casted | acc]}}
          {:error, message} -> {:halt, {:error, "array item #{index}: #{message}"}}
        end
      end)
      |> then(fn
        {:ok, casted_values} -> {:ok, Enum.reverse(casted_values)}
        {:error, message} -> {:error, message}
      end)
    end
  end

  defp cast_value(value, {:enum, allowed}, _coerce?) when is_list(allowed) do
    if value in allowed do
      {:ok, value}
    else
      {:error, "must be one of #{inspect(allowed)}"}
    end
  end

  defp cast_value(_value, type, _coerce?), do: {:error, "unsupported field type #{inspect(type)}"}

  defp cast_primitive(value, :string) when is_binary(value), do: {:ok, value}
  defp cast_primitive(value, :string), do: {:ok, to_string(value)}

  defp cast_primitive(value, :integer) when is_integer(value), do: {:ok, value}

  defp cast_primitive(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "must be an integer"}
    end
  end

  defp cast_primitive(_value, :integer), do: {:error, "must be an integer"}

  defp cast_primitive(value, :float) when is_float(value), do: {:ok, value}
  defp cast_primitive(value, :float) when is_integer(value), do: {:ok, value / 1}

  defp cast_primitive(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "must be a float"}
    end
  end

  defp cast_primitive(_value, :float), do: {:error, "must be a float"}

  defp cast_primitive(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp cast_primitive(value, :boolean) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> {:ok, true}
      "1" -> {:ok, true}
      "yes" -> {:ok, true}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      "no" -> {:ok, false}
      _ -> {:error, "must be a boolean"}
    end
  end

  defp cast_primitive(_value, :boolean), do: {:error, "must be a boolean"}

  defp split_csv(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp field_error(field, message, value) do
    %{path: [:frontmatter, field.name], message: message, value: value}
  end

  defp pretty_label(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
