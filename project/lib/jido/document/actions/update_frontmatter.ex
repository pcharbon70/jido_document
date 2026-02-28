defmodule Jido.Document.Actions.UpdateFrontmatter do
  @moduledoc """
  Applies frontmatter changes to a document with schema-aware validation.
  """

  @behaviour Jido.Document.Action

  alias Jido.Document.{Document, Error}
  alias Jido.Document.Action.Context

  @impl true
  def name, do: :update_frontmatter

  @impl true
  def idempotency, do: :conditionally_idempotent

  @impl true
  def run(params, %Context{} = context) do
    mode = Map.get(params, :mode, :merge)

    with {:ok, document} <- fetch_document(params, context),
         {:ok, changes} <- fetch_changes(params),
         {:ok, updated} <- Document.update_frontmatter(document, changes, mode: mode) do
      {:ok,
       %{
         document: updated,
         changed?: updated.revision != document.revision,
         revision: updated.revision
       }}
    end
  end

  defp fetch_document(params, context) do
    case Map.get(params, :document) || context.document do
      %Document{} = document -> {:ok, document}
      nil -> {:error, Error.new(:invalid_params, "missing document for update_frontmatter", %{})}
      other -> {:error, Error.new(:invalid_params, "invalid document payload", %{value: other})}
    end
  end

  defp fetch_changes(params) do
    case Map.get(params, :changes) do
      changes when is_map(changes) -> {:ok, changes}
      nil -> {:error, Error.new(:invalid_params, "missing frontmatter changes", %{})}
      other -> {:error, Error.new(:invalid_params, "changes must be a map", %{value: other})}
    end
  end
end
