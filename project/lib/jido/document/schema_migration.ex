defmodule Jido.Document.SchemaMigration do
  @moduledoc """
  Frontmatter schema migration helpers with dry-run and safety guards.
  """

  alias Jido.Document.Error

  @type operation ::
          {:rename, atom() | String.t(), atom() | String.t()}
          | {:coerce, atom() | String.t(), :string | :integer | :float | :boolean}
          | {:drop, atom() | String.t()}

  @spec dry_run(map(), [operation()]) :: {:ok, map()} | {:error, Error.t()}
  def dry_run(frontmatter, operations) do
    run(frontmatter, operations, dry_run: true)
  end

  @spec apply(map(), [operation()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def apply(frontmatter, operations, opts \\ []) do
    run(frontmatter, operations, Keyword.put(opts, :dry_run, false))
  end

  defp run(frontmatter, operations, opts) when is_map(frontmatter) and is_list(operations) do
    dry_run? = Keyword.get(opts, :dry_run, true)
    allow_destructive? = Keyword.get(opts, :allow_destructive, false)

    with :ok <- ensure_destructive_allowed(operations, allow_destructive?) do
      {next_frontmatter, changes} =
        Enum.reduce(operations, {frontmatter, []}, fn op, {acc, changes} ->
          case apply_op(acc, op) do
            {:ok, updated, change} -> {updated, [change | changes]}
            {:skip, change} -> {acc, [change | changes]}
            {:error, %Error{} = error} -> throw({:error, error})
          end
        end)

      {:ok,
       %{
         dry_run: dry_run?,
         destructive?: destructive?(operations),
         operations: operations,
         changes: Enum.reverse(changes),
         frontmatter: next_frontmatter
       }}
    else
      {:error, %Error{} = error} ->
        {:error, error}
    end
  catch
    {:error, %Error{} = error} ->
      {:error, error}
  end

  defp run(frontmatter, _operations, _opts) do
    {:error, Error.new(:invalid_params, "frontmatter must be a map", %{frontmatter: frontmatter})}
  end

  defp apply_op(frontmatter, {:rename, from, to}) do
    from_key = normalize_key(from)
    to_key = normalize_key(to)

    cond do
      Map.has_key?(frontmatter, from_key) ->
        value = Map.fetch!(frontmatter, from_key)
        updated = frontmatter |> Map.delete(from_key) |> Map.put(to_key, value)
        {:ok, updated, %{op: :rename, from: from_key, to: to_key}}

      true ->
        {:skip, %{op: :rename, from: from_key, to: to_key, skipped: true}}
    end
  end

  defp apply_op(frontmatter, {:coerce, key, type}) do
    field = normalize_key(key)

    if Map.has_key?(frontmatter, field) do
      value = Map.fetch!(frontmatter, field)

      case coerce(value, type) do
        {:ok, casted} ->
          {:ok, Map.put(frontmatter, field, casted), %{op: :coerce, field: field, type: type}}

        {:error, reason} ->
          {:error,
           Error.new(:validation_failed, "failed to coerce field", %{
             field: field,
             type: type,
             value: value,
             reason: reason
           })}
      end
    else
      {:skip, %{op: :coerce, field: field, type: type, skipped: true}}
    end
  end

  defp apply_op(frontmatter, {:drop, key}) do
    field = normalize_key(key)

    if Map.has_key?(frontmatter, field) do
      {:ok, Map.delete(frontmatter, field), %{op: :drop, field: field}}
    else
      {:skip, %{op: :drop, field: field, skipped: true}}
    end
  end

  defp apply_op(_frontmatter, op) do
    {:error, Error.new(:invalid_params, "unsupported migration operation", %{operation: op})}
  end

  defp coerce(value, :string), do: {:ok, to_string(value)}
  defp coerce(value, :integer) when is_integer(value), do: {:ok, value}

  defp coerce(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp coerce(value, :float) when is_float(value), do: {:ok, value}
  defp coerce(value, :float) when is_integer(value), do: {:ok, value / 1}

  defp coerce(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, :invalid_float}
    end
  end

  defp coerce(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp coerce(value, :boolean) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> {:ok, true}
      "1" -> {:ok, true}
      "yes" -> {:ok, true}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      "no" -> {:ok, false}
      _ -> {:error, :invalid_boolean}
    end
  end

  defp coerce(_value, type), do: {:error, {:unsupported_type, type}}

  defp ensure_destructive_allowed(operations, allow_destructive?) do
    if destructive?(operations) and not allow_destructive? do
      {:error,
       Error.new(:validation_failed, "destructive migration requires explicit confirmation", %{
         operations: operations,
         allow_destructive: allow_destructive?
       })}
    else
      :ok
    end
  end

  defp destructive?(operations), do: Enum.any?(operations, fn op -> match?({:drop, _}, op) end)

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)
end
