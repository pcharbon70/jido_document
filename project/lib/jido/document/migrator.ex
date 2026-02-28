defmodule Jido.Document.Migrator do
  @moduledoc """
  Migration helpers that normalize legacy markdown/frontmatter directories
  to the canonical `Jido.Document` model.
  """

  alias Jido.Document.{Document, Error, Frontmatter, Persistence, SchemaMigration}

  @template_dir Path.expand("../../../priv/migration/templates", __DIR__)
  @default_include_glob "**/*.{md,markdown}"

  @type scalar_type :: :string | :integer | :float | :boolean

  @type mapping :: %{
          rename: %{optional(String.t()) => String.t()},
          coerce: %{optional(String.t()) => scalar_type()},
          drop: [String.t()],
          defaults: map()
        }

  @type entry :: %{
          path: Path.t(),
          relative_path: Path.t(),
          status: :ok | :error,
          changed: boolean(),
          written: boolean(),
          backup_path: Path.t() | nil,
          changes: [map()],
          error: Error.t() | nil
        }

  @type report :: %{
          source_dir: Path.t(),
          dry_run: boolean(),
          include_glob: String.t(),
          mapping: mapping(),
          total_files: non_neg_integer(),
          changed_files: non_neg_integer(),
          written_files: non_neg_integer(),
          failed_files: non_neg_integer(),
          entries: [entry()]
        }

  @spec migrate_directory(Path.t(), keyword()) :: {:ok, report()} | {:error, Error.t()}
  def migrate_directory(directory, opts \\ [])

  def migrate_directory(directory, opts) when is_binary(directory) and is_list(opts) do
    include_glob = Keyword.get(opts, :include_glob, @default_include_glob)
    apply? = Keyword.get(opts, :apply, false)
    dry_run? = not apply?
    allow_destructive? = Keyword.get(opts, :allow_destructive, false)

    with {:ok, source_dir} <- ensure_directory(directory),
         {:ok, mapping} <- resolve_mapping(opts),
         {:ok, files} <- collect_files(source_dir, include_glob),
         {:ok, backup_dir} <- resolve_backup_dir(opts, source_dir) do
      entries =
        Enum.map(files, fn path ->
          migrate_file(path, source_dir, mapping, opts,
            apply?: apply?,
            allow_destructive?: allow_destructive? or dry_run?,
            backup_dir: backup_dir
          )
        end)

      report = build_report(source_dir, include_glob, mapping, dry_run?, entries)
      {:ok, report}
    end
  end

  def migrate_directory(directory, _opts) do
    {:error,
     Error.new(:invalid_params, "directory must be a string path", %{directory: directory})}
  end

  @spec write_report(report(), Path.t()) :: :ok | {:error, Error.t()}
  def write_report(report, path) when is_map(report) and is_binary(path) do
    content = inspect(report, pretty: true, limit: :infinity) <> "\n"

    with :ok <- mkdir_parent(path),
         :ok <- File.write(path, content) do
      :ok
    else
      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to write migration report", %{
           path: path,
           reason: reason
         })}
    end
  end

  def write_report(_report, path) do
    {:error, Error.new(:invalid_params, "report path must be a string", %{path: path})}
  end

  @spec template_names() :: [String.t()]
  def template_names do
    @template_dir
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".exs"))
    |> Enum.sort()
  end

  @spec load_template(String.t()) :: {:ok, mapping()} | {:error, Error.t()}
  def load_template(template_name) when is_binary(template_name) do
    path =
      @template_dir
      |> Path.join(normalize_template_name(template_name) <> ".exs")
      |> Path.expand()

    if File.exists?(path) do
      load_mapping_file(path)
    else
      {:error,
       Error.new(:not_found, "unknown migration template", %{
         template: template_name,
         available_templates: template_names()
       })}
    end
  end

  def load_template(template_name) do
    {:error,
     Error.new(:invalid_params, "template name must be a string", %{template: template_name})}
  end

  @spec load_mapping_file(Path.t()) :: {:ok, mapping()} | {:error, Error.t()}
  def load_mapping_file(path) when is_binary(path) do
    expanded = Path.expand(path)

    if File.regular?(expanded) do
      try do
        {mapping, _binding} = Code.eval_file(expanded)
        normalize_mapping(mapping)
      rescue
        exception ->
          {:error,
           Error.new(:parse_failed, "failed to evaluate mapping file", %{
             path: expanded,
             exception: exception.__struct__,
             message: Exception.message(exception)
           })}
      else
        {:ok, normalized} ->
          {:ok, normalized}

        {:error, %Error{} = error} ->
          {:error, error}

        error ->
          {:error,
           Error.new(:validation_failed, "invalid mapping file", %{
             path: expanded,
             reason: error
           })}
      end
    else
      case File.stat(expanded) do
        {:ok, _stat} ->
          {:error,
           Error.new(:invalid_params, "mapping path must be a regular file", %{path: expanded})}

        {:error, _reason} ->
          {:error, Error.new(:not_found, "mapping file not found", %{path: expanded})}
      end
    end
  end

  def load_mapping_file(path) do
    {:error, Error.new(:invalid_params, "mapping path must be a string", %{path: path})}
  end

  defp ensure_directory(directory) do
    expanded = Path.expand(directory)

    cond do
      not File.exists?(expanded) ->
        {:error, Error.new(:not_found, "source directory does not exist", %{path: expanded})}

      not File.dir?(expanded) ->
        {:error, Error.new(:invalid_params, "source path must be a directory", %{path: expanded})}

      true ->
        {:ok, expanded}
    end
  end

  defp resolve_mapping(opts) do
    mapping_path = Keyword.get(opts, :mapping)
    template_name = Keyword.get(opts, :template)

    cond do
      is_binary(mapping_path) and is_binary(template_name) ->
        {:error,
         Error.new(:invalid_params, "use either mapping file or template, not both", %{
           mapping: mapping_path,
           template: template_name
         })}

      is_binary(mapping_path) ->
        load_mapping_file(mapping_path)

      is_binary(template_name) ->
        load_template(template_name)

      true ->
        {:ok, empty_mapping()}
    end
  end

  defp resolve_backup_dir(opts, source_dir) do
    case Keyword.get(opts, :backup_dir) do
      nil ->
        {:ok, nil}

      backup_dir when is_binary(backup_dir) ->
        {:ok, Path.expand(backup_dir, source_dir)}

      other ->
        {:error, Error.new(:invalid_params, "backup_dir must be a string", %{backup_dir: other})}
    end
  end

  defp collect_files(source_dir, include_glob) do
    if is_binary(include_glob) and String.trim(include_glob) != "" do
      files =
        source_dir
        |> Path.join(include_glob)
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)
        |> Enum.sort()

      {:ok, files}
    else
      {:error,
       Error.new(:invalid_params, "include_glob must be a non-empty string", %{
         include_glob: include_glob
       })}
    end
  end

  defp migrate_file(path, source_dir, mapping, opts, migrate_opts) do
    syntax_override = normalize_syntax(Keyword.get(opts, :syntax))
    line_endings = normalize_line_endings(Keyword.get(opts, :line_endings, :lf))
    emit_empty_frontmatter = Keyword.get(opts, :emit_empty_frontmatter, false)
    apply? = Keyword.fetch!(migrate_opts, :apply?)
    allow_destructive? = Keyword.fetch!(migrate_opts, :allow_destructive?)
    backup_dir = Keyword.get(migrate_opts, :backup_dir)

    result =
      with {:ok, raw} <- read_file(path),
           {:ok, split} <- Frontmatter.split(raw),
           {:ok, parsed_frontmatter} <- parse_frontmatter(split.frontmatter, split.syntax, path),
           {:ok, migration} <- apply_mapping(parsed_frontmatter, mapping, allow_destructive?),
           {:ok, serialized} <-
             serialize_document(path, raw, split.body, migration.frontmatter,
               syntax_override: syntax_override || split.syntax || :yaml,
               line_endings: line_endings,
               emit_empty_frontmatter: emit_empty_frontmatter
             ),
           changed? = serialized != raw,
           {:ok, write_info} <-
             maybe_write_file(path, source_dir, raw, serialized, changed?, backup_dir, apply?) do
        {:ok,
         %{
           path: path,
           relative_path: Path.relative_to(path, source_dir),
           status: :ok,
           changed: changed?,
           written: write_info.written,
           backup_path: write_info.backup_path,
           changes: migration.changes,
           error: nil
         }}
      end

    case result do
      {:ok, entry} ->
        entry

      {:error, %Error{} = error} ->
        %{
          path: path,
          relative_path: Path.relative_to(path, source_dir),
          status: :error,
          changed: false,
          written: false,
          backup_path: nil,
          changes: [],
          error: Error.merge_details(error, %{path: path})
        }
    end
  end

  defp parse_frontmatter(source, syntax, path) do
    case Frontmatter.parse(source, syntax) do
      {:ok, frontmatter} when is_map(frontmatter) ->
        {:ok, normalize_frontmatter(frontmatter)}

      {:error, %{message: message} = details} ->
        {:error,
         Error.new(:parse_failed, "frontmatter parse failed: #{message}", %{
           path: path,
           details: details
         })}
    end
  end

  defp apply_mapping(frontmatter, mapping, allow_destructive?) do
    operations = mapping_operations(mapping)

    with {:ok, migration} <- run_operations(frontmatter, operations, allow_destructive?) do
      with_defaults =
        Enum.reduce(mapping.defaults, migration.frontmatter, fn {key, value}, acc ->
          Map.put_new(acc, normalize_key(key), value)
        end)

      {:ok, %{migration | frontmatter: with_defaults}}
    end
  end

  defp run_operations(frontmatter, [], _allow_destructive?) do
    {:ok, %{changes: [], operations: [], frontmatter: frontmatter}}
  end

  defp run_operations(frontmatter, operations, allow_destructive?) do
    case SchemaMigration.apply(frontmatter, operations, allow_destructive: allow_destructive?) do
      {:ok, migration} ->
        {:ok, migration}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp serialize_document(path, raw, body, frontmatter, opts) do
    with {:ok, document} <-
           Document.new(
             path: path,
             raw: raw,
             body: body,
             frontmatter: frontmatter
           ),
         {:ok, serialized} <-
           Document.serialize(
             document,
             syntax: Keyword.fetch!(opts, :syntax_override),
             line_endings: Keyword.fetch!(opts, :line_endings),
             emit_empty_frontmatter: Keyword.fetch!(opts, :emit_empty_frontmatter)
           ) do
      {:ok, serialized}
    else
      {:error, [error | _] = errors} ->
        message =
          case error do
            %{message: value} -> value
            _ -> "document validation failed during migration"
          end

        {:error,
         Error.new(:validation_failed, message, %{
           errors: errors
         })}
    end
  end

  defp maybe_write_file(_path, _source_dir, _raw, _serialized, false, _backup_dir, _apply?) do
    {:ok, %{written: false, backup_path: nil}}
  end

  defp maybe_write_file(_path, _source_dir, _raw, _serialized, true, _backup_dir, false) do
    {:ok, %{written: false, backup_path: nil}}
  end

  defp maybe_write_file(path, source_dir, raw, serialized, true, backup_dir, true) do
    with {:ok, backup_path} <- maybe_write_backup(path, source_dir, backup_dir, raw),
         {:ok, _snapshot} <- Persistence.atomic_write(path, serialized) do
      {:ok, %{written: true, backup_path: backup_path}}
    else
      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp maybe_write_backup(_path, _source_dir, nil, _raw), do: {:ok, nil}

  defp maybe_write_backup(path, source_dir, backup_dir, raw) do
    relative_path = Path.relative_to(path, source_dir)
    target_path = Path.join(backup_dir, relative_path)

    with :ok <- mkdir_parent(target_path),
         :ok <- File.write(target_path, raw) do
      {:ok, target_path}
    else
      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to write backup file", %{
           source_path: path,
           backup_path: target_path,
           reason: reason
         })}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, content}

      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to read source file", %{path: path, reason: reason})}
    end
  end

  defp mkdir_parent(path) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_report(source_dir, include_glob, mapping, dry_run?, entries) do
    total_files = length(entries)
    changed_files = Enum.count(entries, & &1.changed)
    written_files = Enum.count(entries, & &1.written)
    failed_files = Enum.count(entries, &(&1.status == :error))

    %{
      source_dir: source_dir,
      dry_run: dry_run?,
      include_glob: include_glob,
      mapping: mapping,
      total_files: total_files,
      changed_files: changed_files,
      written_files: written_files,
      failed_files: failed_files,
      entries: entries
    }
  end

  defp mapping_operations(mapping) do
    rename_ops =
      Enum.map(mapping.rename, fn {from, to} ->
        {:rename, normalize_key(from), normalize_key(to)}
      end)

    coerce_ops =
      Enum.map(mapping.coerce, fn {field, type} ->
        {:coerce, normalize_key(field), type}
      end)

    drop_ops =
      Enum.map(mapping.drop, fn field ->
        {:drop, normalize_key(field)}
      end)

    rename_ops ++ coerce_ops ++ drop_ops
  end

  defp normalize_mapping(mapping) when is_map(mapping) do
    rename = normalize_rename_map(Map.get(mapping, :rename) || Map.get(mapping, "rename", %{}))

    with {:ok, rename_map} <- rename,
         {:ok, coerce_map} <-
           normalize_coerce_map(Map.get(mapping, :coerce) || Map.get(mapping, "coerce", %{})),
         {:ok, drop_list} <-
           normalize_drop_list(Map.get(mapping, :drop) || Map.get(mapping, "drop", [])),
         {:ok, defaults} <-
           normalize_defaults_map(
             Map.get(mapping, :defaults) || Map.get(mapping, "defaults", %{})
           ) do
      {:ok,
       %{
         rename: rename_map,
         coerce: coerce_map,
         drop: drop_list,
         defaults: defaults
       }}
    end
  end

  defp normalize_mapping(other) do
    {:error, Error.new(:validation_failed, "mapping must evaluate to a map", %{mapping: other})}
  end

  defp empty_mapping do
    %{
      rename: %{},
      coerce: %{},
      drop: [],
      defaults: %{}
    }
  end

  defp normalize_rename_map(rename) when is_map(rename) do
    {:ok,
     Enum.into(rename, %{}, fn {from, to} ->
       {normalize_key(from), normalize_key(to)}
     end)}
  end

  defp normalize_rename_map(other) do
    {:error, Error.new(:validation_failed, "mapping.rename must be a map", %{rename: other})}
  end

  defp normalize_coerce_map(coerce) when is_map(coerce) do
    coerce
    |> Enum.reduce_while({:ok, %{}}, fn {field, type}, {:ok, acc} ->
      case normalize_scalar_type(type) do
        {:ok, normalized} ->
          {:cont, {:ok, Map.put(acc, normalize_key(field), normalized)}}

        {:error, %Error{} = error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp normalize_coerce_map(other) do
    {:error, Error.new(:validation_failed, "mapping.coerce must be a map", %{coerce: other})}
  end

  defp normalize_drop_list(drop) when is_list(drop) do
    {:ok, Enum.map(drop, &normalize_key/1)}
  end

  defp normalize_drop_list(other) do
    {:error, Error.new(:validation_failed, "mapping.drop must be a list", %{drop: other})}
  end

  defp normalize_defaults_map(defaults) when is_map(defaults) do
    {:ok,
     Enum.into(defaults, %{}, fn {key, value} ->
       {normalize_key(key), value}
     end)}
  end

  defp normalize_defaults_map(other) do
    {:error, Error.new(:validation_failed, "mapping.defaults must be a map", %{defaults: other})}
  end

  defp normalize_scalar_type(type) when type in [:string, :integer, :float, :boolean],
    do: {:ok, type}

  defp normalize_scalar_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "string" -> {:ok, :string}
      "integer" -> {:ok, :integer}
      "float" -> {:ok, :float}
      "boolean" -> {:ok, :boolean}
      _ -> {:error, Error.new(:validation_failed, "unsupported coerce type", %{type: type})}
    end
  end

  defp normalize_scalar_type(type) do
    {:error, Error.new(:validation_failed, "unsupported coerce type", %{type: type})}
  end

  defp normalize_frontmatter(frontmatter) do
    Enum.into(frontmatter, %{}, fn {key, value} ->
      {normalize_key(key), value}
    end)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp normalize_syntax(nil), do: nil
  defp normalize_syntax(:yaml), do: :yaml
  defp normalize_syntax(:toml), do: :toml

  defp normalize_syntax(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "yaml" -> :yaml
      "toml" -> :toml
      other -> raise ArgumentError, "unsupported syntax override: #{inspect(other)}"
    end
  end

  defp normalize_syntax(other),
    do:
      raise(
        ArgumentError,
        "syntax override must be :yaml, :toml, \"yaml\", or \"toml\" (got #{inspect(other)})"
      )

  defp normalize_line_endings(:lf), do: :lf
  defp normalize_line_endings(:crlf), do: :crlf

  defp normalize_line_endings(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "lf" -> :lf
      "crlf" -> :crlf
      other -> raise ArgumentError, "unsupported line_endings: #{inspect(other)}"
    end
  end

  defp normalize_line_endings(other),
    do:
      raise(
        ArgumentError,
        "line_endings must be :lf, :crlf, \"lf\", or \"crlf\" (got #{inspect(other)})"
      )

  defp normalize_template_name(name) do
    name
    |> String.trim()
    |> String.trim_trailing(".exs")
  end
end
