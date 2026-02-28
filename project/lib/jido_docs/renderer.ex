defmodule JidoDocs.Renderer do
  @moduledoc """
  Renderer boundary for markdown preview generation.
  """

  alias JidoDocs.Adapters.Renderer, as: RendererAdapter

  @type output :: RendererAdapter.output()
  @type result :: {:ok, output()} | {:error, JidoDocs.Error.t()}

  @spec to_html(String.t(), keyword()) :: result()
  def to_html(body, opts \\ []) do
    adapter = Keyword.get(opts, :adapter, JidoDocs.Adapters.Renderer.Mdex)
    fallback_adapter = Keyword.get(opts, :fallback_adapter, JidoDocs.Adapters.Renderer.Fallback)

    case RendererAdapter.render(adapter, body, opts) do
      {:ok, payload} ->
        {:ok, payload}

      {:error, _reason} ->
        RendererAdapter.render(fallback_adapter, body, opts)
    end
  end
end
