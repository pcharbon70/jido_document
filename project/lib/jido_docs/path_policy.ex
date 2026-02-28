defmodule JidoDocs.PathPolicy do
  @moduledoc """
  Filesystem path resolution and workspace-boundary enforcement.
  """

  alias JidoDocs.Error

  @spec resolve_path(String.t(), keyword() | map()) :: {:ok, Path.t()} | {:error, Error.t()}
  def resolve_path(path, opts \\ [])

  def resolve_path(path, opts) when is_binary(path) do
    opts = to_map(opts)

    workspace_root =
      opts
      |> Map.get(:workspace_root, File.cwd!())
      |> Path.expand()

    resolved =
      if Path.type(path) == :absolute do
        Path.expand(path)
      else
        Path.expand(path, workspace_root)
      end

    if within_workspace?(resolved, workspace_root) do
      {:ok, resolved}
    else
      {:error,
       Error.new(
         :filesystem_error,
         "path escapes workspace root",
         %{path: path, resolved: resolved, workspace_root: workspace_root}
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
end
