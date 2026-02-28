defmodule JidoDocs.Adapters.Renderer do
  @moduledoc """
  Markdown rendering adapter boundary.
  """

  alias JidoDocs.Error

  @type output :: %{
          required(:html) => String.t(),
          required(:toc) => list(),
          required(:diagnostics) => list()
        }

  @callback to_html(String.t(), keyword()) :: {:ok, output()} | {:error, term()}

  @spec render(module(), String.t(), keyword()) :: {:ok, output()} | {:error, Error.t()}
  def render(adapter, markdown, opts \\ []) do
    case adapter.to_html(markdown, opts) do
      {:ok, %{html: html} = payload} when is_binary(html) ->
        {:ok, payload}

      {:ok, other} ->
        Error.wrap(:invalid_input, :renderer_returned_invalid_payload, %{payload: other})

      {:error, reason} ->
        Error.wrap(:renderer_unavailable, reason, %{adapter: adapter})

      other ->
        Error.wrap(:upstream_error, :unexpected_renderer_response, %{
          adapter: adapter,
          response: other
        })
    end
  end
end
