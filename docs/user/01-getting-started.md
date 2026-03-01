# 01 - Getting Started

This guide covers the minimum setup to start a document session and run a full
load-update-render-save flow.

## Components in this guide

- `Jido.Document`
- `Jido.Document.Agent`
- `Jido.Document.Action.Result`

## 1. Add the dependency

```elixir
def deps do
  [
    {:jido_document, "~> 0.1"}
  ]
end
```

Then install:

```bash
mix deps.get
```

## 2. Run a minimal lifecycle

```elixir
Application.ensure_all_started(:jido_document)

alias Jido.Document.Agent
alias Jido.Document.Action.Result

workspace_root = Path.expand(".")
tmp_dir = Path.join(workspace_root, "tmp/jido_document_user_guide")
File.mkdir_p!(tmp_dir)

path = Path.join(tmp_dir, "getting_started.md")
File.write!(path, "---\ntitle: \"Getting Started\"\n---\nHello\n")

{:ok, agent} = Jido.Document.start_session(session_id: "user-guide-01")

context_opts = [context_options: %{workspace_root: workspace_root}]

{:ok, _loaded, _meta} =
  Agent.command(agent, :load, %{path: path}, context_opts)
  |> Result.unwrap()

{:ok, _updated, _meta} =
  Agent.command(agent, :update_body, %{body: "Updated from guide 01\n"})
  |> Result.unwrap()

{:ok, preview_payload, _meta} =
  Agent.command(agent, :render, %{})
  |> Result.unwrap()

{:ok, saved, _meta} =
  Agent.command(agent, :save, %{path: path}, context_opts)
  |> Result.unwrap()

IO.puts("Rendered HTML bytes: #{byte_size(preview_payload.preview.html)}")
IO.puts("Saved bytes: #{saved.bytes}")
```

## 3. What happens in this flow

- `:load` parses frontmatter and markdown into a canonical document struct.
- `:update_body` edits in-memory markdown and bumps revision state.
- `:render` produces preview output (`html`, `toc`, `diagnostics`).
- `:save` serializes and writes to disk with divergence protection.

## Next

Continue with [02 - Document Structure: Frontmatter and Markdown](./02-document-structure-frontmatter-and-markdown.md).

