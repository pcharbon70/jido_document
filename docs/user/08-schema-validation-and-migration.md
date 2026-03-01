# 08 - Schema Validation and Migration

This guide covers strict frontmatter contracts and migration workflows.

## Components in this guide

- `Jido.Document.Field`
- `Jido.Document.Schema`
- `Jido.Document.SchemaMigration`
- `Jido.Document.Migrator`
- `mix jido.migrate_docs`

## 1. Define a schema for frontmatter

```elixir
defmodule BlogSchema do
  @behaviour Jido.Document.Schema
  alias Jido.Document.Field

  @impl true
  def fields do
    [
      %Field{name: :title, type: :string, required: true},
      %Field{name: :slug, type: :string, required: true},
      %Field{name: :published, type: :boolean, default: false},
      %Field{name: :tags, type: {:array, :string}}
    ]
  end
end
```

## 2. Validate frontmatter maps

```elixir
alias Jido.Document.Schema

frontmatter = %{"title" => "Hello", "slug" => "hello", "published" => "true"}

{:ok, normalized, warnings} =
  Schema.validate_frontmatter(frontmatter, BlogSchema, unknown_keys: :warn)
```

`unknown_keys` policies:

- `:warn`
- `:ignore`
- `:reject`

## 3. Run schema migration operations

```elixir
alias Jido.Document.SchemaMigration

ops = [
  {:rename, "name", "title"},
  {:coerce, "priority", :integer}
]

{:ok, dry_run} = SchemaMigration.dry_run(%{"name" => "Doc", "priority" => "3"}, ops)
{:ok, applied} = SchemaMigration.apply(%{"name" => "Doc", "priority" => "3"}, ops)
```

Destructive operations such as `{:drop, key}` require `allow_destructive: true`.

## 4. Migrate whole directories

Dry run:

```bash
mix jido.migrate_docs --source ./content --template blog_frontmatter
```

Apply changes with backups:

```bash
mix jido.migrate_docs \
  --source ./content \
  --template blog_frontmatter \
  --apply \
  --backup-dir ./migration_backups
```

List bundled templates:

```bash
mix jido.migrate_docs --list-templates
```

## 5. Production recommendation

- Use `dry_run` first.
- Save reports with `--report`.
- Apply in controlled batches.
- Keep backups until post-migration validation passes.

