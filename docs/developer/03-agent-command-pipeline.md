# 03 - Agent Command Pipeline

`Jido.Document.Agent` is the stateful orchestrator. It owns:

- active `Document`
- history model
- checkpoint and recovery state
- revision sequence
- preview/fallback state
- audit trail window

## Command execution flow

```mermaid
sequenceDiagram
  participant Caller
  participant Agent as Jido.Document.Agent
  participant Action as Jido.Document.Action
  participant Impl as Jido.Document.Actions.*

  Caller->>Agent: command(session, action, params, opts)
  Agent->>Agent: normalize params + inject defaults
  Agent->>Agent: guard action / lock if needed
  Agent->>Action: execute(action_module, params, context)
  Action->>Action: authorize + telemetry wrapper
  Action->>Impl: run(params, context)
  Impl-->>Action: {:ok, value} | {:error, reason}
  Action-->>Agent: Result.t()
  Agent->>Agent: apply_success/apply_failure
  Agent->>Agent: history/revision/audit/signal updates
  Agent-->>Caller: Result.t()
```

## Key contracts

- Action behavior (`Jido.Document.Action`):
  - `name/0`
  - `idempotency/0`
  - `run/2`
- Result envelope (`Jido.Document.Action.Result`):
  - `status`
  - `value` or `error`
  - metadata (`action`, `idempotency`, `correlation_id`, `duration_us`)
- Context envelope (`Jido.Document.Action.Context`):
  - session identity, actor, document snapshot, options

## Cross-cutting behaviors in pipeline

- Authorization:
  - applied in `Action.execute/3`
  - role matrix + optional custom hook policy
- Retry:
  - controlled by `Jido.Document.Reliability.with_retry/2`
  - retries only retryable errors
- Optimistic rollback:
  - failed mutation actions can revert to previous state
- Render fallback:
  - on render failure, agent emits a fallback preview payload

## Sync vs async

- Sync mode (`mode: :sync`):
  - `GenServer.call`, immediate `Result.t()`.
- Async mode (`mode: :async`):
  - `GenServer.cast`, returns `:ok`.

## History commands

`:undo` and `:redo` are handled via history transitions and require a loaded
document. They update revision/audit metadata similarly to regular actions.

