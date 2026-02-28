defmodule Jido.Document.Phase4RenderingPipelineIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Document.Renderer

  test "renders headings links lists tables and fenced code" do
    markdown = """
    # Title

    A [link](https://example.com)

    - one
    - two

    | col | value |
    | --- | ----- |
    | a   | b     |

    ```elixir
    IO.puts(:ok)
    ```
    """

    assert {:ok, preview} = Renderer.render(markdown)

    assert String.contains?(preview.html, "<h1 id=\"title\">Title</h1>")
    assert String.contains?(preview.html, "<a href=\"https://example.com\">link</a>")
    assert String.contains?(preview.html, "<li>one</li>")
    assert String.contains?(preview.html, "md-table-row")
    assert String.contains?(preview.html, "language-elixir")

    assert [%{id: "title", href: "#title", title: "Title"}] = preview.toc
    assert is_binary(preview.cache_key)
    assert byte_size(preview.cache_key) == 64
  end

  test "returns diagnostics for malformed frontmatter and unsupported code language" do
    markdown = """
    ---
    title: hello
    # Missing closing frontmatter delimiter

    ```weirdlang
    value
    ```
    """

    assert {:ok, preview} = Renderer.render(markdown)

    assert Enum.any?(preview.diagnostics, fn diag -> diag.code == :frontmatter_warning end)
    assert Enum.any?(preview.diagnostics, fn diag -> diag.code == :unsupported_code_language end)
  end

  test "produces deterministic output and cache keys for identical input" do
    markdown = "# Deterministic\n\nBody\n"

    assert {:ok, preview1} = Renderer.render(markdown, adapter: :simple, plugins: [])
    assert {:ok, preview2} = Renderer.render(markdown, adapter: :simple, plugins: [])

    assert preview1.html == preview2.html
    assert preview1.cache_key == preview2.cache_key
    assert preview1.toc == preview2.toc
  end
end
