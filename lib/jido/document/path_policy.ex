defmodule Jido.Document.PathPolicy do
  @moduledoc """
  Filesystem path resolution and workspace-boundary enforcement.
  """

  alias Jido.Document.Error

  @spec resolve_path(String.t(), keyword() | map()) :: {:ok, Path.t()} | {:error, Error.t()}
  def resolve_path(path, opts \\ [])

  def resolve_path(path, opts) when is_binary(path) do
    opts = to_map(opts)

    workspace_root_input = Map.get(opts, :workspace_root, File.cwd!())
    workspace_root = canonicalize_path(workspace_root_input)
    resolved = canonicalize_candidate(path, workspace_root)

    if within_workspace?(resolved, workspace_root) do
      {:ok, resolved}
    else
      {:error,
       Error.new(
         :filesystem_error,
         "path escapes workspace root policy",
         %{
           policy: :workspace_boundary,
           path: path,
           resolved: resolved,
           workspace_root: workspace_root
         }
       )}
    end
  end

  def resolve_path(path, _opts) do
    {:error, Error.new(:invalid_params, "path must be a string", %{path: path})}
  end

  defp within_workspace?(resolved, workspace_root) do
    normalized_root = String.trim_trailing(workspace_root, "/") <> "/"
    resolved == workspace_root or String.starts_with?(resolved, normalized_root)
  end

  defp to_map(%{} = map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(_), do: %{}

  defp canonicalize_candidate(path, workspace_root) do
    expanded =
      if Path.type(path) == :absolute do
        Path.expand(path)
      else
        Path.expand(path, workspace_root)
      end

    canonicalize_path(expanded)
  end

  defp canonicalize_path(path) do
    path
    |> Path.expand()
    |> resolve_known_symlinks()
  end

  defp resolve_known_symlinks(path) do
    {base, segments} = split_base(path)
    resolve_segments(base, segments)
  end

  defp split_base(path) do
    parts = Path.split(path)

    case parts do
      ["/" | rest] -> {"/", rest}
      [base | rest] -> {base, rest}
      [] -> {"/", []}
    end
  end

  defp resolve_segments(current, []), do: current

  defp resolve_segments(current, [segment | rest]) do
    candidate = Path.join(current, segment)

    case File.lstat(candidate) do
      {:ok, %File.Stat{type: :symlink}} ->
        case File.read_link(candidate) do
          {:ok, link_target} ->
            target =
              if Path.type(link_target) == :absolute do
                Path.expand(link_target)
              else
                Path.expand(link_target, Path.dirname(candidate))
              end

            resolve_segments(target, rest)

          {:error, _} ->
            resolve_segments(candidate, rest)
        end

      {:ok, _} ->
        resolve_segments(candidate, rest)

      {:error, :enoent} ->
        Path.expand(Path.join([segment | rest]), current)

      {:error, _} ->
        resolve_segments(candidate, rest)
    end
  end
end
