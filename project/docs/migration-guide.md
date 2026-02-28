# Migration Guide

This guide covers migration from existing markdown/frontmatter directories
into the canonical `Jido.Document` model.

## Scope

- Input: markdown files with optional YAML (`---`) or TOML (`+++`) frontmatter.
- Output: canonicalized frontmatter + markdown body serialization.
- Non-goals: UI migration or transport-layer migration.

## Migration command

Dry-run (default):

```bash
mix jido.migrate_docs --source ./content
```

Apply changes in place with backups:

```bash
mix jido.migrate_docs \
  --source ./content \
  --template blog_frontmatter \
  --apply \
  --backup-dir ./migration_backups \
  --report ./migration_report.exs
```

Use custom mapping rules:

```bash
mix jido.migrate_docs \
  --source ./content \
  --mapping ./priv/migration/custom_mapping.exs \
  --apply \
  --allow-destructive
```

List bundled templates:

```bash
mix jido.migrate_docs --list-templates
```

## Staged rollout strategy

1. Run dry-run against a representative subset and inspect `changed_files` and
   `failed_files`.
2. Apply on a canary directory with `--backup-dir` enabled.
3. Run normal session flows (`load`, `update`, `render`, `save`) on migrated
   canary data.
4. Expand rollout in batches while monitoring error rates and audit traces.
5. Keep migration reports per batch for post-rollout traceability.

## Rollback strategy

1. Stop new writes to the affected directory.
2. Restore original files from `--backup-dir` into the source directory.
3. Re-run dry-run migration to verify state is back to the pre-migration shape.
4. Address mapping defects, then re-run canary migration before broader rollout.

## Operational guardrails

- Use `--allow-destructive` only when `drop` mappings are intentional and reviewed.
- Keep backups outside the source directory to avoid recursive processing.
- Commit mapping template changes in version control with code review.
- Store migration report artifacts for incident reconstruction.
