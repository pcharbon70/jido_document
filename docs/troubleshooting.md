# Troubleshooting and Diagnostics

## Common failures

### `:filesystem_error` with `workspace_boundary`
Cause:
- Load/save path escapes configured workspace root.

Resolution:
1. Confirm `context_options.workspace_root`.
2. Resolve symlink/traversal segments in the target path.
3. Retry with a path under the workspace root.

### `:forbidden` authorization denial
Cause:
- Actor role set does not satisfy action permission matrix.

Resolution:
1. Inspect deny signal (`action: :authorize`) payload.
2. Update actor roles or authorization matrix policy.
3. Retry operation with permitted actor context.

### `:conflict` on save
Cause:
- On-disk file diverged from baseline snapshot.

Resolution:
1. Reload and merge.
2. Use explicit conflict strategy (`:overwrite` or `:merge_hook`) if policy allows.

### Render degraded mode
Cause:
- Repeated render failures triggered circuit breaker.

Resolution:
1. Inspect `:degraded_mode` signal payload.
2. Fix renderer/plugin configuration.
3. Wait for cooldown then retry render.

## Useful diagnostics

### Session state

```elixir
state = Jido.Document.Agent.state(agent)
```

### Trace bundle export

```elixir
trace = Jido.Document.Agent.export_trace(agent, limit: 200)
```

### Recovery status

```elixir
pending = Jido.Document.Agent.recovery_status(agent)
```

### Queue metrics

```elixir
stats = Jido.Document.Render.JobQueue.stats()
```

## Pre-release health checklist

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix jido.api_manifest --check
mix test
```
