defmodule Jido.Document.PublicApi do
  @moduledoc """
  Stable public API manifest builder.

  This module defines the semver-governed API surface and provides helpers to
  snapshot and validate it during release checks.
  """

  @schema_version 1

  @stable_modules [
    Jido.Document,
    Jido.Document.Agent,
    Jido.Document.Document,
    Jido.Document.Frontmatter,
    Jido.Document.Renderer,
    Jido.Document.SchemaMigration,
    Jido.Document.SessionRegistry,
    Jido.Document.Signal,
    Jido.Document.SignalBus
  ]

  @stable_functions %{
    Jido.Document => [
      {:start_session, 0},
      {:start_session, 1}
    ],
    Jido.Document.Agent => [
      {:start_link, 0},
      {:start_link, 1},
      {:command, 2},
      {:command, 3},
      {:command, 4},
      {:subscribe, 1},
      {:subscribe, 2},
      {:unsubscribe, 1},
      {:unsubscribe, 2},
      {:state, 1},
      {:recovery_status, 1},
      {:recover, 1},
      {:recover, 2},
      {:discard_recovery, 1},
      {:export_trace, 1},
      {:export_trace, 2},
      {:list_recovery_candidates, 0},
      {:list_recovery_candidates, 1}
    ],
    Jido.Document.Document => [
      {:blank, 0},
      {:blank, 1},
      {:new, 0},
      {:new, 1},
      {:from_map, 1},
      {:parse, 1},
      {:parse, 2},
      {:serialize, 1},
      {:serialize, 2},
      {:validate, 1},
      {:valid?, 1},
      {:ensure_valid!, 1},
      {:touch, 1},
      {:mark_dirty, 1},
      {:mark_clean, 1},
      {:update_frontmatter, 2},
      {:update_frontmatter, 3},
      {:update_body, 2},
      {:update_body, 3},
      {:apply_body_patch, 2},
      {:apply_body_patch, 3},
      {:canonicalize, 1},
      {:canonicalize, 2}
    ],
    Jido.Document.Frontmatter => [
      {:split, 1},
      {:parse, 2},
      {:serialize, 2},
      {:delimiter_for, 1}
    ],
    Jido.Document.Renderer => [
      {:render, 1},
      {:render, 2},
      {:cache_key, 3},
      {:fallback_preview, 2},
      {:fallback_preview, 3}
    ],
    Jido.Document.SchemaMigration => [
      {:dry_run, 2},
      {:apply, 2},
      {:apply, 3}
    ],
    Jido.Document.SessionRegistry => [
      {:start_link, 0},
      {:start_link, 1},
      {:session_id_for_path, 1},
      {:ensure_session, 1},
      {:ensure_session, 2},
      {:ensure_session, 3},
      {:ensure_session_by_path, 1},
      {:ensure_session_by_path, 2},
      {:ensure_session_by_path, 3},
      {:fetch_session, 1},
      {:fetch_session, 2},
      {:list_sessions, 0},
      {:list_sessions, 1},
      {:acquire_lock, 2},
      {:acquire_lock, 3},
      {:acquire_lock, 4},
      {:validate_lock, 2},
      {:validate_lock, 3},
      {:release_lock, 2},
      {:release_lock, 3},
      {:force_takeover, 2},
      {:force_takeover, 3},
      {:force_takeover, 4},
      {:reclaim_idle, 1},
      {:reclaim_idle, 2},
      {:touch, 1},
      {:touch, 2}
    ],
    Jido.Document.Signal => [
      {:known_types, 0},
      {:build, 3},
      {:build, 4},
      {:to_message, 1}
    ],
    Jido.Document.SignalBus => [
      {:start_link, 0},
      {:start_link, 1},
      {:subscribe, 1},
      {:subscribe, 2},
      {:subscribe, 3},
      {:unsubscribe, 1},
      {:unsubscribe, 2},
      {:unsubscribe, 3},
      {:broadcast, 3},
      {:broadcast, 4},
      {:broadcast, 5},
      {:subscribers, 1},
      {:subscribers, 2}
    ]
  }

  @spec stable_modules() :: [module()]
  def stable_modules, do: @stable_modules

  @spec manifest() :: map()
  def manifest do
    %{
      schema_version: @schema_version,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      semver_policy: "docs/semver-policy.md",
      release_blocking_criteria: "docs/release-blocking-criteria.md",
      modules: Enum.map(@stable_modules, &module_contract/1)
    }
  end

  @spec manifest_without_timestamp() :: map()
  def manifest_without_timestamp do
    manifest()
    |> Map.delete(:generated_at)
  end

  @spec validate_contract() :: :ok | {:error, map()}
  def validate_contract do
    missing =
      Enum.flat_map(@stable_modules, fn module ->
        exports = MapSet.new(module.__info__(:functions))

        @stable_functions
        |> Map.fetch!(module)
        |> Enum.reject(&MapSet.member?(exports, &1))
        |> Enum.map(fn function -> %{module: module, function: function} end)
      end)

    if missing == [], do: :ok, else: {:error, %{missing_functions: missing}}
  end

  @spec default_manifest_path() :: Path.t()
  def default_manifest_path do
    Path.expand("priv/api/public_api_manifest.exs", File.cwd!())
  end

  @spec write_manifest(Path.t() | nil) :: :ok | {:error, term()}
  def write_manifest(path \\ nil) do
    path = path || default_manifest_path()
    manifest = manifest_without_timestamp()
    content = inspect(manifest, pretty: true, limit: :infinity) <> "\n"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, content) do
      :ok
    end
  end

  @spec read_manifest(Path.t() | nil) :: {:ok, map()} | {:error, term()}
  def read_manifest(path \\ nil) do
    path = path || default_manifest_path()

    case Code.eval_file(path) do
      {manifest, _binding} when is_map(manifest) -> {:ok, manifest}
      {other, _binding} -> {:error, {:invalid_manifest, other}}
    end
  rescue
    error -> {:error, error}
  end

  defp module_contract(module) do
    %{
      module: inspect(module),
      functions: public_functions(module)
    }
  end

  defp public_functions(module) do
    @stable_functions
    |> Map.fetch!(module)
    |> Enum.sort()
    |> Enum.map(fn {name, arity} -> %{name: Atom.to_string(name), arity: arity} end)
  end
end
