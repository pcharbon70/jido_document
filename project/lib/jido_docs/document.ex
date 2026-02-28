defmodule JidoDocs.Document do
  @moduledoc """
  Canonical in-memory representation of a frontmatter + markdown document.

  This module owns base invariants and mutation tracking semantics used by
  higher-level parse/update/save workflows.
  """

  alias JidoDocs.Frontmatter
  alias JidoDocs.Schema

  @typedoc "Structured invariant error with field path context."
  @type validation_error :: %{
          path: [atom() | String.t()],
          message: String.t(),
          value: term()
        }

  @type t :: %__MODULE__{
          path: Path.t() | nil,
          frontmatter: map(),
          body: String.t(),
          raw: String.t(),
          schema: module() | nil,
          dirty: boolean(),
          revision: non_neg_integer()
        }

  defstruct path: nil,
            frontmatter: %{},
            body: "",
            raw: "",
            schema: nil,
            dirty: false,
            revision: 0

  @spec blank(keyword()) :: t()
  def blank(opts \\ []) do
    %__MODULE__{
      path: Keyword.get(opts, :path),
      schema: Keyword.get(opts, :schema),
      raw: Keyword.get(opts, :raw, ""),
      body: Keyword.get(opts, :body, ""),
      frontmatter: Keyword.get(opts, :frontmatter, %{}),
      dirty: Keyword.get(opts, :dirty, false),
      revision: Keyword.get(opts, :revision, 0)
    }
  end

  @spec new(keyword()) :: {:ok, t()} | {:error, [validation_error()]}
  def new(opts \\ []) when is_list(opts) do
    opts
    |> blank()
    |> validate()
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, [validation_error()]}
  def from_map(%{} = attrs) do
    attrs
    |> Enum.into([])
    |> new()
  end

  @spec parse(String.t(), keyword()) :: {:ok, t()} | {:error, [validation_error()]}
  def parse(raw_content, opts \\ []) when is_binary(raw_content) and is_list(opts) do
    with {:ok, %{frontmatter: fm_source, body: body, syntax: syntax}} <-
           Frontmatter.split(raw_content),
         {:ok, frontmatter} <- Frontmatter.parse(fm_source, syntax),
         {:ok, doc} <-
           new(
             path: Keyword.get(opts, :path),
             schema: Keyword.get(opts, :schema),
             raw: raw_content,
             body: body,
             frontmatter: frontmatter,
             dirty: false,
             revision: Keyword.get(opts, :revision, 0)
           ) do
      {:ok, doc}
    else
      {:error, error} when is_map(error) -> {:error, [error]}
      {:error, errors} when is_list(errors) -> {:error, errors}
    end
  end

  @spec serialize(t(), keyword()) :: {:ok, String.t()} | {:error, [validation_error()]}
  def serialize(%__MODULE__{} = doc, opts \\ []) when is_list(opts) do
    syntax = Keyword.get(opts, :syntax, :yaml)
    emit_empty_frontmatter = Keyword.get(opts, :emit_empty_frontmatter, false)

    with {:ok, normalized_doc} <- validate(doc),
         {:ok, fm_content} <- Frontmatter.serialize(normalized_doc.frontmatter, syntax) do
      if map_size(normalized_doc.frontmatter) == 0 and not emit_empty_frontmatter do
        {:ok, normalized_doc.body}
      else
        delimiter = Frontmatter.delimiter_for(syntax)

        serialized =
          delimiter <> "\n" <> fm_content <> "\n" <> delimiter <> "\n" <> normalized_doc.body

        {:ok, serialized}
      end
    else
      {:error, error} when is_map(error) -> {:error, [error]}
      {:error, errors} when is_list(errors) -> {:error, errors}
    end
  end

  @spec validate(t() | map()) :: {:ok, t()} | {:error, [validation_error()]}
  def validate(%__MODULE__{} = doc) do
    errors =
      []
      |> check_path(doc.path)
      |> check_frontmatter(doc.frontmatter)
      |> check_body(doc.body)
      |> check_raw(doc.raw)
      |> check_schema(doc.schema)
      |> check_dirty(doc.dirty)
      |> check_revision(doc.revision)
      |> check_schema_compatibility(doc)

    case errors do
      [] -> {:ok, doc}
      _ -> {:error, errors}
    end
  end

  def validate(%{} = attrs), do: from_map(attrs)

  @spec valid?(t() | map()) :: boolean()
  def valid?(doc_or_map) do
    match?({:ok, _}, validate(doc_or_map))
  end

  @spec ensure_valid!(t() | map()) :: t()
  def ensure_valid!(doc_or_map) do
    case validate(doc_or_map) do
      {:ok, doc} -> doc
      {:error, errors} -> raise ArgumentError, format_errors(errors)
    end
  end

  @doc """
  Marks a document as mutated.

  Semantics:
  - `dirty` is set to `true`
  - `revision` increments by one
  """
  @spec touch(t()) :: t()
  def touch(%__MODULE__{} = doc) do
    %{doc | dirty: true, revision: doc.revision + 1}
  end

  @spec mark_dirty(t()) :: t()
  def mark_dirty(%__MODULE__{} = doc), do: touch(doc)

  @doc """
  Marks the document as clean after successful persistence.
  """
  @spec mark_clean(t()) :: t()
  def mark_clean(%__MODULE__{} = doc) do
    %{doc | dirty: false}
  end

  defp check_path(errors, nil), do: errors

  defp check_path(errors, path) when is_binary(path) do
    errors
  end

  defp check_path(errors, path) do
    [error([:path], "must be nil or a path string", path) | errors]
  end

  defp check_frontmatter(errors, frontmatter) when is_map(frontmatter), do: errors

  defp check_frontmatter(errors, frontmatter) do
    [error([:frontmatter], "must be a map", frontmatter) | errors]
  end

  defp check_body(errors, body) when is_binary(body), do: errors

  defp check_body(errors, body) do
    [error([:body], "must be a string", body) | errors]
  end

  defp check_raw(errors, raw) when is_binary(raw), do: errors

  defp check_raw(errors, raw) do
    [error([:raw], "must be a string", raw) | errors]
  end

  defp check_schema(errors, nil), do: errors

  defp check_schema(errors, schema) when is_atom(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :fields, 0) do
      errors
    else
      [error([:schema], "must export fields/0", schema) | errors]
    end
  end

  defp check_schema(errors, schema) do
    [error([:schema], "must be nil or a module", schema) | errors]
  end

  defp check_dirty(errors, dirty) when is_boolean(dirty), do: errors

  defp check_dirty(errors, dirty) do
    [error([:dirty], "must be a boolean", dirty) | errors]
  end

  defp check_revision(errors, revision) when is_integer(revision) and revision >= 0, do: errors

  defp check_revision(errors, revision) do
    [error([:revision], "must be a non-negative integer", revision) | errors]
  end

  defp check_schema_compatibility(errors, %{schema: nil}), do: errors

  defp check_schema_compatibility(errors, %{schema: schema, frontmatter: frontmatter}) do
    case Schema.validate_frontmatter(frontmatter, schema, unknown_keys: :ignore) do
      {:ok, _normalized, _warnings} ->
        errors

      {:error, schema_errors} ->
        converted =
          Enum.map(schema_errors, fn schema_error ->
            error(schema_error.path, schema_error.message, schema_error.value)
          end)

        converted ++ errors
    end
  end

  defp error(path, message, value) do
    %{path: path, message: message, value: value}
  end

  defp format_errors(errors) do
    "Document invariant violation(s): " <>
      Enum.map_join(Enum.reverse(errors), "; ", fn err ->
        "#{Enum.join(Enum.map(err.path, &to_string/1), ".")}: #{err.message} (#{inspect(err.value)})"
      end)
  end
end
