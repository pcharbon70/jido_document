defmodule JidoDocs.Actions.Render do
  @moduledoc """
  Renders document body into preview artifacts (HTML/TOC/diagnostics).
  """

  @behaviour JidoDocs.Action

  alias JidoDocs.{Document, Error, Renderer}
  alias JidoDocs.Action.Context

  @impl true
  def name, do: :render

  @impl true
  def idempotency, do: :idempotent

  @impl true
  def run(params, %Context{} = context) do
    with {:ok, document} <- fetch_document(params, context),
         {:ok, preview} <- Renderer.render(document.body, Map.get(params, :render_opts, [])) do
      {:ok, %{preview: preview, revision: document.revision, document: document}}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.from_reason({:render, reason}, %{})}
    end
  end

  defp fetch_document(params, context) do
    case Map.get(params, :document) || context.document do
      %Document{} = document -> {:ok, document}
      nil -> {:error, Error.new(:invalid_params, "missing document for render", %{})}
      other -> {:error, Error.new(:invalid_params, "invalid document payload", %{value: other})}
    end
  end
end
