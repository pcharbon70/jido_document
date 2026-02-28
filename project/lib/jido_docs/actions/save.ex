defmodule JidoDocs.Actions.Save do
  @moduledoc """
  Serializes and persists a document to disk.
  """

  @behaviour JidoDocs.Action

  alias JidoDocs.{Document, Error, PathPolicy}
  alias JidoDocs.Action.Context

  @impl true
  def name, do: :save

  @impl true
  def idempotency, do: :conditionally_idempotent

  @impl true
  def run(params, %Context{} = context) do
    with {:ok, document} <- fetch_document(params, context),
         {:ok, resolved_path} <- resolve_save_path(params, context, document),
         {:ok, serialized} <- Document.serialize(document, Map.get(params, :serialize_opts, [])),
         :ok <- write_file_safely(resolved_path, serialized) do
      {:ok,
       %{
         document: Document.mark_clean(document),
         path: resolved_path,
         bytes: byte_size(serialized),
         revision: document.revision
       }}
    end
  end

  defp fetch_document(params, context) do
    case Map.get(params, :document) || context.document do
      %Document{} = document -> {:ok, document}
      nil -> {:error, Error.new(:invalid_params, "missing document for save", %{})}
      other -> {:error, Error.new(:invalid_params, "invalid document payload", %{value: other})}
    end
  end

  defp resolve_save_path(params, context, %Document{} = document) do
    path = Map.get(params, :path) || context.path || document.path
    PathPolicy.resolve_path(path, context.options)
  end

  defp write_file_safely(path, content) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, tmp_path} <- write_temp_file(path, content),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to write file", %{path: path, reason: reason})}

      :error ->
        {:error, Error.new(:filesystem_error, "failed to rename temp file", %{path: path})}
    end
  end

  defp write_temp_file(path, content) do
    tmp_path = path <> ".tmp." <> Integer.to_string(System.unique_integer([:positive]))

    case File.write(tmp_path, content) do
      :ok -> {:ok, tmp_path}
      {:error, reason} -> {:error, reason}
    end
  end
end
