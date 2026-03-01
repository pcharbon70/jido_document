# 03 - Working with the Document API

This guide focuses on pure document operations without running a session
process.

## Components in this guide

- `Jido.Document.Document`

## 1. Build and validate documents in memory

```elixir
alias Jido.Document.Document

{:ok, doc} =
  Document.new(
    path: "/tmp/demo.md",
    frontmatter: %{title: "Demo", priority: 1},
    body: "Initial body\n"
  )
```

Validation rules include:

- `frontmatter` must be a map
- `body` must be a string
- `path`, when set, must be a string

## 2. Apply edits

```elixir
{:ok, doc1} = Document.update_frontmatter(doc, %{owner: "ops"}, mode: :merge)
{:ok, doc2} = Document.apply_body_patch(doc1, %{search: "Initial", replace: "Updated"})
{:ok, doc3} = Document.update_body(doc2, "Updated body with LF\r\n", line_endings: :lf)
```

`apply_body_patch/3` supports:

- full replacement string
- patch map (`search`/`replace`/`global`)
- unary function (`fn body -> ... end`)

## 3. Normalize and serialize deterministically

```elixir
canonical = Document.canonicalize(doc3, line_endings: :lf, trailing_whitespace: :trim)
{:ok, output} = Document.serialize(canonical, syntax: :yaml)
```

## 4. Parse-serialize roundtrip pattern

```elixir
{:ok, parsed} = Document.parse(output)
{:ok, output_again} = Document.serialize(parsed, syntax: :yaml)
```

For stable pipelines, compare `output == output_again`.

## Next

Continue with [04 - Session Workflows with Agent](./04-session-workflows-with-agent.md).

