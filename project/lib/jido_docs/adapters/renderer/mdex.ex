defmodule JidoDocs.Adapters.Renderer.Mdex do
  @moduledoc """
  `Mdex` renderer adapter.
  """

  @behaviour JidoDocs.Adapters.Renderer

  @impl true
  def to_html(markdown, _opts) when is_binary(markdown) do
    cond do
      Code.ensure_loaded?(Mdex) and function_exported?(Mdex, :to_html, 1) ->
        html = apply(Mdex, :to_html, [markdown])
        {:ok, %{html: html, toc: [], diagnostics: []}}

      true ->
        {:error, :mdex_renderer_unavailable}
    end
  end
end
