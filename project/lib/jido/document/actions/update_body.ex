defmodule Jido.Document.Actions.UpdateBody do
  @moduledoc """
  Applies body replacement or patch operations while maintaining revision state.
  """

  @behaviour Jido.Document.Action

  alias Jido.Document.{Document, Error}
  alias Jido.Document.Action.Context

  @impl true
  def name, do: :update_body

  @impl true
  def idempotency, do: :conditionally_idempotent

  @impl true
  def run(params, %Context{} = context) do
    with {:ok, document} <- fetch_document(params, context),
         {:ok, updated} <- apply_update(document, params) do
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
      nil -> {:error, Error.new(:invalid_params, "missing document for update_body", %{})}
      other -> {:error, Error.new(:invalid_params, "invalid document payload", %{value: other})}
    end
  end

  defp apply_update(document, %{body: body} = params) when is_binary(body) do
    normalize_opts = Map.get(params, :normalize, [])
    Document.update_body(document, body, normalize_opts)
  end

  defp apply_update(document, %{patch: patch} = params) do
    normalize_opts = Map.get(params, :normalize, [])
    Document.apply_body_patch(document, patch, normalize_opts)
  end

  defp apply_update(_document, params) do
    {:error,
     Error.new(
       :invalid_params,
       "update_body requires :body or :patch",
       %{params: params}
     )}
  end
end
