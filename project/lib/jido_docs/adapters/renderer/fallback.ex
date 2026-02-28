defmodule JidoDocs.Adapters.Renderer.Fallback do
  @moduledoc """
  Safe fallback markdown renderer when external renderers are unavailable.
  """

  @behaviour JidoDocs.Adapters.Renderer

  @impl true
  def to_html(markdown, _opts) when is_binary(markdown) do
    escaped =
      markdown
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

    {:ok,
     %{
       html: "<pre>#{escaped}</pre>",
       toc: [],
       diagnostics: [%{level: :warning, message: "Fallback renderer active"}]
     }}
  end
end
