# 07 - Session Registry, Locking, and Signals

Multi-client coordination is handled by `SessionRegistry` and `SignalBus`.

## Session registry responsibilities

- deterministic file-based session id generation
- lazy session startup under `SessionSupervisor`
- path-to-session indexing
- idle-session reclaim
- optimistic lock ownership with revisioned tokens

## Lock lifecycle

```mermaid
stateDiagram-v2
  [*] --> Unlocked
  Unlocked --> Locked: acquire_lock(owner)
  Locked --> Locked: validate_lock(token)
  Locked --> Unlocked: release_lock(valid token)
  Locked --> Locked: force_takeover(new owner)
```

## Lock semantics

- `acquire_lock/4`:
  - returns `lock_token`, `lock_revision`, owner
- `validate_lock/3`:
  - optimistic token check for write-authorized caller
- `release_lock/3`:
  - token-required release
- `force_takeover/4`:
  - operator override path with `previous_owner`

## Signal bus model

`Jido.Document.SignalBus` provides session-scoped fanout with queue-aware
dropping.

```mermaid
flowchart LR
  Agent["Session Agent"] --> Build["Signal.build/4"]
  Build --> Bus["SignalBus.broadcast/5"]
  Bus --> SubA["Subscriber A"]
  Bus --> SubB["Subscriber B"]
  Bus --> Drop["Drop when queue > max_queue_len"]
```

Design notes:

- Signals are versioned (`schema_version`) and type-checked.
- Payloads are size-bounded with truncation metadata.
- Monitoring cleans up dead subscriber PIDs automatically.

