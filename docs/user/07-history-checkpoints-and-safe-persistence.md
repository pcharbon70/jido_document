# 07 - History, Checkpoints, and Safe Persistence

This guide covers reliability features used in production editing workflows.

## Components in this guide

- `Jido.Document.Agent` (`:undo`, `:redo`, recovery APIs)
- `Jido.Document.Persistence` (through `:save`)
- `Jido.Document.Safety` (through `:render` and `:save`)

## 1. History-based undo and redo

```elixir
alias Jido.Document.Agent

%{status: :ok} = Agent.command(agent, :update_body, %{body: "Body v1\n"})
%{status: :ok} = Agent.command(agent, :update_body, %{body: "Body v2\n"})

%{status: :ok, value: undo_value} = Agent.command(agent, :undo, %{})
%{status: :ok, value: redo_value} = Agent.command(agent, :redo, %{})

IO.puts(undo_value.document.body)
IO.puts(redo_value.document.body)
```

## 2. Checkpoint and recovery lifecycle

```elixir
{:ok, recovering_agent} =
  Agent.start_link(
    session_id: "recoverable-session",
    checkpoint_dir: Path.expand("tmp/checkpoints"),
    checkpoint_on_edit: true,
    autosave_interval_ms: 15_000
  )

pending = Agent.recovery_status(recovering_agent)

case pending do
  nil -> :ok
  _checkpoint -> Agent.recover(recovering_agent)
end
```

Other recovery utilities:

- `Agent.discard_recovery/1`
- `Agent.list_recovery_candidates/1`

## 3. Save divergence protection

Session saves include a baseline disk snapshot by default. If file content on
disk diverges externally, save returns a conflict error unless you choose an
explicit conflict strategy.

```elixir
Agent.command(agent, :save, %{
  path: path,
  on_conflict: :overwrite
})
```

Conflict policies:

- `:reject` (default)
- `:overwrite`
- `:merge_hook`

## 4. Sensitive content checks

Safety options can be applied to render and save operations:

```elixir
safety = %{block_severities: [:high], approved_codes: ["email"]}

Agent.command(agent, :render, %{safety: safety})
Agent.command(agent, :save, %{path: path, safety: safety})
```

If high-severity findings are unapproved, save is blocked.

## Next

Continue with [08 - Schema Validation and Migration](./08-schema-validation-and-migration.md).

