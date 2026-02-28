defmodule Jido.Document.Actions.Load do
  @moduledoc """
  Loads a markdown document from disk and parses frontmatter/body into
  `Jido.Document.Document`.
  """

  @behaviour Jido.Document.Action

  alias Jido.Document.{Document, Error, PathPolicy, Persistence}
  alias Jido.Document.Action.Context

  @impl true
  def name, do: :load

  @impl true
  def idempotency, do: :idempotent

  @impl true
  def run(params, %Context{} = context) do
    path = Map.get(params, :path) || context.path
    schema = Map.get(params, :schema) || context.options[:schema]

    with {:ok, resolved_path} <- PathPolicy.resolve_path(path, context.options),
         {:ok, raw} <- read_file(resolved_path),
         {:ok, document} <- Document.parse(raw, path: resolved_path, schema: schema),
         {:ok, disk_snapshot} <- Persistence.snapshot(resolved_path) do
      {:ok,
       %{
         document: document,
         path: resolved_path,
         bytes: byte_size(raw),
         revision: document.revision,
         disk_snapshot: disk_snapshot
       }}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} ->
        {:ok, content}

      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to read file", %{path: path, reason: reason})}
    end
  end
end
