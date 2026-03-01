# 05 - Rendering and Preview Pipeline

This guide focuses on preview generation and render diagnostics.

## Components in this guide

- `Jido.Document.Renderer`
- `Jido.Document.Actions.Render` (via `Agent.command/4`)

## 1. Render directly from markdown

~~~elixir
alias Jido.Document.Renderer

markdown = """
---
title: "Render Demo"
---
# Heading

```elixir
IO.puts("hello")
```
"""

{:ok, preview} = Renderer.render(markdown, adapter: :auto, strip_frontmatter: true)

IO.puts("adapter=#{preview.adapter}")
IO.puts("toc_count=#{length(preview.toc)}")
IO.puts("diagnostics=#{length(preview.diagnostics)}")
~~~

Preview payload keys:

- `html`
- `toc`
- `diagnostics`
- `cache_key`
- `adapter`
- `metadata`

## 2. Render through an active session

```elixir
alias Jido.Document.Agent
alias Jido.Document.Action.Result

{:ok, payload, _meta} =
  Agent.command(agent, :render, %{render_opts: [adapter: :simple]})
  |> Result.unwrap()

preview = payload.preview
IO.puts(preview.html)
```

## 3. Render options you will likely use

- `adapter`: `:mdex`, `:simple`, or `:auto`
- `strip_frontmatter`: remove frontmatter from preview source
- `syntax_highlight`: theme and language support controls
- `plugins`: transform pipeline hooks
- `max_code_block_lines`: truncate very large fenced blocks

## 4. Fallback behavior

When primary rendering fails, the session-level render flow provides a fallback
preview so clients still have readable output while reporting diagnostics.

## Next

Continue with [06 - Concurrency with Session Registry](./06-concurrency-with-session-registry.md).
