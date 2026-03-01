# 02 - Document Structure: Frontmatter and Markdown

This guide explains how `Jido.Document` models a document as:

- frontmatter map
- markdown body string

Frontmatter is optional. Markdown-only documents are valid.

## Components in this guide

- `Jido.Document.Document`
- `Jido.Document.Frontmatter`

## 1. Supported frontmatter delimiters

- YAML frontmatter: `---`
- TOML frontmatter: `+++`

Examples:

```markdown
---
title: "YAML Example"
count: 3
---
# Body
```

```markdown
+++
title = "TOML Example"
count = 3
+++
# Body
```

```markdown
# Markdown Only

No frontmatter is present.
```

## 2. Parse into the canonical struct

```elixir
alias Jido.Document.Document

{:ok, yaml_doc} =
  Document.parse("---\ntitle: \"Hello\"\ncount: 3\n---\n# Body\n")

{:ok, plain_doc} =
  Document.parse("# Markdown only\n")

yaml_doc.frontmatter
# => %{"count" => 3, "title" => "Hello"}

plain_doc.frontmatter
# => %{}
```

## 3. Serialize back to file content

```elixir
{:ok, content} = Document.serialize(yaml_doc, syntax: :yaml)
{:ok, body_only} = Document.serialize(plain_doc)
{:ok, forced_frontmatter} = Document.serialize(plain_doc, emit_empty_frontmatter: true)
```

Behavior:

- Empty frontmatter is omitted by default.
- `emit_empty_frontmatter: true` forces delimiters even for empty metadata.

## 4. Update frontmatter and body

```elixir
{:ok, doc1} = Document.update_frontmatter(yaml_doc, %{author: "Pascal"}, mode: :merge)
{:ok, doc2} = Document.update_body(doc1, "# Updated Body\r\n", line_endings: :lf)
```

`mode` options for frontmatter updates:

- `:merge` (default): merge keys
- `:replace`: replace the entire frontmatter map

## Next

Continue with [03 - Working with the Document API](./03-working-with-the-document-api.md).

