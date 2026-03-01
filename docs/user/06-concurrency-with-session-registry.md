# 06 - Concurrency with Session Registry

This guide covers multi-client coordination and lock ownership.

## Components in this guide

- `Jido.Document.SessionRegistry`
- `Jido.Document.SessionSupervisor`

## 1. Ensure a session by path

```elixir
alias Jido.Document.SessionRegistry

path = Path.expand("tmp/concurrent_doc.md")
File.mkdir_p!(Path.dirname(path))
File.write!(path, "# Concurrency demo\n")

{:ok, session} = SessionRegistry.ensure_session_by_path(SessionRegistry, path)

IO.puts("session_id=#{session.session_id}")
IO.puts("pid=#{inspect(session.pid)}")
```

## 2. Acquire and validate locks

```elixir
{:ok, lock} = SessionRegistry.acquire_lock(SessionRegistry, session.session_id, "client-a")

:ok =
  SessionRegistry.validate_lock(
    SessionRegistry,
    session.session_id,
    lock.lock_token
  )
```

If another client tries to lock the same session, it receives a conflict error.

## 3. Force takeover for operational recovery

```elixir
{:ok, takeover} =
  SessionRegistry.force_takeover(
    SessionRegistry,
    session.session_id,
    "client-b",
    reason: "operator override"
  )
```

Takeover payload includes:

- new `lock_token`
- incremented `lock_revision`
- `previous_owner`

## 4. Release and reclaim

```elixir
:ok = SessionRegistry.release_lock(SessionRegistry, session.session_id, takeover.lock_token)
{:ok, reclaimed_ids} = SessionRegistry.reclaim_idle(SessionRegistry, 60_000)
```

## 5. Deterministic IDs for file sessions

```elixir
session_id = SessionRegistry.session_id_for_path(path)
```

Use this when you need stable session identity across restarts.

## Next

Continue with [07 - History, Checkpoints, and Safe Persistence](./07-history-checkpoints-and-safe-persistence.md).

