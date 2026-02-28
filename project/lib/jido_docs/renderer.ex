defmodule JidoDocs.Renderer do
  @moduledoc """
  Markdown rendering facade for preview generation.

  The current implementation prioritizes deterministic output and schema-stable
  payloads over full Markdown feature coverage.
  """

  @type heading :: %{level: pos_integer(), id: String.t(), title: String.t()}

  @type output :: %{
          html: String.t(),
          toc: [heading()],
          diagnostics: [map()]
        }

  @spec render(String.t(), keyword()) :: {:ok, output()} | {:error, JidoDocs.Error.t()}
  def render(markdown, _opts \\ []) when is_binary(markdown) do
    headings = extract_headings(markdown)

    html =
      markdown
      |> String.split("\n", trim: false)
      |> Enum.map_join("\n", &line_to_html/1)

    {:ok, %{html: html, toc: headings, diagnostics: []}}
  rescue
    exception ->
      {:error,
       JidoDocs.Error.from_exception(exception, %{
         component: :renderer,
         operation: :render_markdown
       })}
  end

  defp extract_headings(markdown) do
    markdown
    |> String.split("\n", trim: false)
    |> Enum.reduce([], fn line, acc ->
      case Regex.run(~r/^(#+)\s+(.+)$/, line) do
        [_, hashes, title] ->
          id = heading_id(title)
          [%{level: String.length(hashes), id: id, title: String.trim(title)} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp heading_id(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end

  defp line_to_html(""), do: ""

  defp line_to_html(line) do
    case Regex.run(~r/^(#+)\s+(.+)$/, line) do
      [_, hashes, title] ->
        level = String.length(hashes)
        id = heading_id(title)
        "<h#{level} id=\"#{id}\">#{escape_html(String.trim(title))}</h#{level}>"

      _ ->
        "<p>#{escape_html(line)}</p>"
    end
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
