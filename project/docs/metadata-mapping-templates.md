# Metadata Mapping Templates

Mapping templates translate legacy frontmatter keys into canonical fields.

Bundled templates live under `priv/migration/templates/*.exs` and are selected with:

```bash
mix jido.migrate_docs --source ./content --template <name>
```

## Template format

Each template is an Elixir map:

```elixir
%{
  rename: %{"old_key" => "new_key"},
  coerce: %{"draft" => :boolean, "priority" => :integer},
  drop: ["legacy_key"],
  defaults: %{"status" => "draft"}
}
```

## Semantics

- `rename`: renames keys before validation and serialization.
- `coerce`: casts scalar fields to `:string`, `:integer`, `:float`, or `:boolean`.
- `drop`: removes legacy fields (requires `--allow-destructive` during apply mode).
- `defaults`: fills missing keys without overriding existing values.

## Included templates

- `blog_frontmatter`: common blog/article frontmatter field renames and defaults.
- `knowledge_base`: internal KB ownership/review metadata normalization.

## Custom templates

Create a custom mapping file and pass `--mapping path/to/file.exs`. The file must
evaluate to the same map shape shown above.
