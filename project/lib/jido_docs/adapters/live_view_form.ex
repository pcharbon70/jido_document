defmodule JidoDocs.Adapters.LiveViewForm do
  @moduledoc """
  Schema-driven field mapping for LiveView-friendly form data.
  """

  alias JidoDocs.{Field, Schema}

  @type field_form :: %{
          name: atom(),
          label: String.t(),
          type: Field.field_type(),
          component: atom(),
          required: boolean(),
          value: term(),
          options: [term()],
          hint: String.t() | nil,
          error: String.t() | nil
        }

  @type t :: %{
          fields: [field_form()],
          errors: %{optional(atom()) => String.t()},
          hints: %{optional(atom()) => String.t()}
        }

  @spec build(module() | nil, map(), keyword()) :: t()
  def build(schema, frontmatter, opts \\ [])

  def build(nil, _frontmatter, _opts), do: %{fields: [], errors: %{}, hints: %{}}

  def build(schema, frontmatter, opts) when is_atom(schema) and is_map(frontmatter) do
    errors = field_messages(Keyword.get(opts, :errors, []))
    hints = field_messages(Keyword.get(opts, :warnings, []))

    fields =
      schema_fields(schema)
      |> Enum.map(fn %Field{} = field ->
        name = field.name

        %{
          name: name,
          label: field.label || humanize(name),
          type: field.type,
          component: component_for(field.type),
          required: field.required,
          value: fetch_value(frontmatter, field),
          options: field.options,
          hint: message_for_field(hints, name) || default_hint(field.type),
          error: message_for_field(errors, name)
        }
      end)

    %{fields: fields, errors: errors, hints: hints}
  end

  @spec validate_and_build(module() | nil, map(), keyword()) :: {t(), [map()]}
  def validate_and_build(schema, frontmatter, opts \\ [])

  def validate_and_build(nil, frontmatter, opts) do
    {build(nil, frontmatter, opts), []}
  end

  def validate_and_build(schema, frontmatter, opts)
      when is_atom(schema) and is_map(frontmatter) do
    validation_opts = Keyword.get(opts, :validation_opts, unknown_keys: :warn)

    case Schema.validate_frontmatter(frontmatter, schema, validation_opts) do
      {:ok, normalized, warnings} ->
        {build(schema, normalized, warnings: warnings), []}

      {:error, errors} ->
        {build(schema, frontmatter, errors: errors), errors}
    end
  end

  defp schema_fields(schema) do
    cond do
      not Code.ensure_loaded?(schema) -> []
      not function_exported?(schema, :fields, 0) -> []
      true -> Enum.map(schema.fields(), &normalize_field/1)
    end
  end

  defp normalize_field(%Field{} = field), do: field
  defp normalize_field(%{} = field), do: struct(Field, field)

  defp fetch_value(frontmatter, %Field{name: name, default: default}) do
    Map.get(frontmatter, name, Map.get(frontmatter, Atom.to_string(name), default))
  end

  defp component_for(:boolean), do: :checkbox
  defp component_for(:integer), do: :number_input
  defp component_for(:float), do: :number_input
  defp component_for({:enum, _}), do: :select
  defp component_for({:array, _}), do: :tag_input
  defp component_for(_), do: :text_input

  defp field_messages(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn
      %{path: [:frontmatter, name], message: message}, acc
      when is_atom(name) and is_binary(message) ->
        Map.put(acc, name, message)

      %{path: [:frontmatter, name], message: message}, acc
      when is_binary(name) and is_binary(message) ->
        Map.put(acc, name, message)

      _entry, acc ->
        acc
    end)
  end

  defp field_messages(_), do: %{}

  defp default_hint(:boolean), do: "Use true/false"
  defp default_hint({:array, _}), do: "Comma-separated values are accepted"

  defp default_hint({:enum, allowed}),
    do: "Allowed values: #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"

  defp default_hint(_), do: nil

  defp message_for_field(messages, name) do
    Map.get(messages, name) || Map.get(messages, Atom.to_string(name))
  end

  defp humanize(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
