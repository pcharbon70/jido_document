defmodule JidoDocs.Config do
  @moduledoc """
  Runtime configuration schema, defaults, and normalization.

  Precedence order is deterministic:
  `call options > session options > application config > built-in defaults`.
  """

  @default_parser %{
    default_syntax: :yaml,
    supported_syntaxes: [:yaml, :toml],
    delimiters: %{yaml: "---", toml: "+++"}
  }

  @default_renderer %{
    adapter: JidoDocs.Adapters.Renderer.Mdex,
    fallback_adapter: JidoDocs.Adapters.Renderer.Fallback,
    debounce_ms: 120,
    timeout_ms: 5_000,
    queue_limit: 100
  }

  @default_persistence %{
    autosave_interval_ms: 30_000,
    temp_dir: ".jido_docs/tmp",
    backup_extension: ".bak",
    atomic_writes: true
  }

  @default_config %{
    parser: @default_parser,
    renderer: @default_renderer,
    persistence: @default_persistence,
    workspace_root: nil
  }

  @type validation_error :: %{
          path: [atom()],
          message: String.t(),
          value: term()
        }

  @type t :: %__MODULE__{
          parser: map(),
          renderer: map(),
          persistence: map(),
          workspace_root: Path.t()
        }

  defstruct parser: @default_parser,
            renderer: @default_renderer,
            persistence: @default_persistence,
            workspace_root: File.cwd!()

  @spec default_map() :: map()
  def default_map, do: @default_config

  @spec load(keyword() | map(), keyword() | map()) :: {:ok, t()} | {:error, [validation_error()]}
  def load(call_opts \\ %{}, session_opts \\ %{}) do
    app_config = Application.get_env(:project, __MODULE__, %{})

    merged =
      @default_config
      |> deep_merge(to_map(app_config))
      |> deep_merge(to_map(session_opts))
      |> deep_merge(to_map(call_opts))

    normalize(merged)
  end

  @spec normalize(map()) :: {:ok, t()} | {:error, [validation_error()]}
  def normalize(config) when is_map(config) do
    {workspace_root, workspace_errors} =
      normalize_workspace_root(Map.get(config, :workspace_root))

    {parser, parser_errors} = normalize_parser(Map.get(config, :parser, %{}))

    {renderer, renderer_errors} = normalize_renderer(Map.get(config, :renderer, %{}))

    {persistence, persistence_errors} =
      normalize_persistence(Map.get(config, :persistence, %{}), workspace_root)

    errors = workspace_errors ++ parser_errors ++ renderer_errors ++ persistence_errors

    case errors do
      [] ->
        {:ok,
         %__MODULE__{
           parser: parser,
           renderer: renderer,
           persistence: persistence,
           workspace_root: workspace_root
         }}

      _ ->
        {:error, errors}
    end
  end

  defp normalize_workspace_root(nil), do: {Path.expand(File.cwd!()), []}

  defp normalize_workspace_root(workspace_root) when is_binary(workspace_root) do
    expanded = Path.expand(workspace_root)

    if File.dir?(expanded) do
      {expanded, []}
    else
      {expanded,
       [
         validation_error(
           [:workspace_root],
           "must point to an existing directory",
           workspace_root
         )
       ]}
    end
  end

  defp normalize_workspace_root(other) do
    {Path.expand(File.cwd!()),
     [validation_error([:workspace_root], "must be a string path", other)]}
  end

  defp normalize_parser(parser) when is_map(parser) do
    merged = deep_merge(@default_parser, parser)

    errors =
      []
      |> maybe_error(
        merged.default_syntax in [:yaml, :toml],
        [:parser, :default_syntax],
        "must be :yaml or :toml",
        merged.default_syntax
      )
      |> maybe_error(
        is_list(merged.supported_syntaxes) and
          Enum.all?(merged.supported_syntaxes, &(&1 in [:yaml, :toml])),
        [:parser, :supported_syntaxes],
        "must be a list containing only :yaml and :toml",
        merged.supported_syntaxes
      )
      |> maybe_error(
        is_binary(get_in(merged, [:delimiters, :yaml])) and
          is_binary(get_in(merged, [:delimiters, :toml])),
        [:parser, :delimiters],
        "must include binary delimiters for :yaml and :toml",
        merged.delimiters
      )

    {merged, errors}
  end

  defp normalize_parser(other) do
    {@default_parser, [validation_error([:parser], "must be a map", other)]}
  end

  defp normalize_renderer(renderer) when is_map(renderer) do
    merged = deep_merge(@default_renderer, renderer)

    errors =
      []
      |> maybe_error(
        is_atom(merged.adapter),
        [:renderer, :adapter],
        "must be a module atom",
        merged.adapter
      )
      |> maybe_error(
        is_atom(merged.fallback_adapter),
        [:renderer, :fallback_adapter],
        "must be a module atom",
        merged.fallback_adapter
      )
      |> maybe_error(
        is_integer(merged.debounce_ms) and merged.debounce_ms >= 0,
        [:renderer, :debounce_ms],
        "must be an integer >= 0",
        merged.debounce_ms
      )
      |> maybe_error(
        is_integer(merged.timeout_ms) and merged.timeout_ms > 0,
        [:renderer, :timeout_ms],
        "must be an integer > 0",
        merged.timeout_ms
      )
      |> maybe_error(
        is_integer(merged.queue_limit) and merged.queue_limit > 0,
        [:renderer, :queue_limit],
        "must be an integer > 0",
        merged.queue_limit
      )

    {merged, errors}
  end

  defp normalize_renderer(other) do
    {@default_renderer, [validation_error([:renderer], "must be a map", other)]}
  end

  defp normalize_persistence(persistence, workspace_root) when is_map(persistence) do
    merged = deep_merge(@default_persistence, persistence)

    temp_dir = normalize_temp_dir(merged.temp_dir, workspace_root)
    merged = Map.put(merged, :temp_dir, temp_dir)

    errors =
      []
      |> maybe_error(
        is_integer(merged.autosave_interval_ms) and merged.autosave_interval_ms >= 0,
        [:persistence, :autosave_interval_ms],
        "must be an integer >= 0",
        merged.autosave_interval_ms
      )
      |> maybe_error(
        is_binary(merged.temp_dir),
        [:persistence, :temp_dir],
        "must be a valid path string",
        merged.temp_dir
      )
      |> maybe_error(
        is_binary(merged.backup_extension),
        [:persistence, :backup_extension],
        "must be a string",
        merged.backup_extension
      )
      |> maybe_error(
        is_boolean(merged.atomic_writes),
        [:persistence, :atomic_writes],
        "must be a boolean",
        merged.atomic_writes
      )

    {merged, errors}
  end

  defp normalize_persistence(other, _workspace_root) do
    {@default_persistence, [validation_error([:persistence], "must be a map", other)]}
  end

  defp normalize_temp_dir(temp_dir, workspace_root) when is_binary(temp_dir) do
    if Path.type(temp_dir) == :absolute do
      Path.expand(temp_dir)
    else
      Path.expand(Path.join(workspace_root, temp_dir))
    end
  end

  defp normalize_temp_dir(other, _workspace_root), do: other

  defp maybe_error(errors, true, _path, _message, _value), do: errors

  defp maybe_error(errors, false, path, message, value) do
    errors ++ [validation_error(path, message, value)]
  end

  defp validation_error(path, message, value) do
    %{path: path, message: message, value: value}
  end

  defp to_map(%{} = map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(nil), do: %{}
  defp to_map(_other), do: %{}

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, base_value, override_value ->
      if is_map(base_value) and is_map(override_value) do
        deep_merge(base_value, override_value)
      else
        override_value
      end
    end)
  end
end
