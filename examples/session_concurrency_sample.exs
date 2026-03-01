Application.ensure_all_started(:jido_document)

alias Jido.Document.SessionRegistry

session_id = "example-concurrency-" <> Integer.to_string(System.unique_integer([:positive]))

{:ok, session} = SessionRegistry.ensure_session(SessionRegistry, session_id)
IO.puts("session_started=#{session.session_id}")

{:ok, lock_a} = SessionRegistry.acquire_lock(SessionRegistry, session_id, "client-a")
IO.puts("lock_owner=client-a lock_revision=#{lock_a.lock_revision}")

{:error, conflict} = SessionRegistry.acquire_lock(SessionRegistry, session_id, "client-b")
IO.puts("conflict_code=#{conflict.code} owner=#{conflict.details.owner}")

{:ok, takeover} =
  SessionRegistry.force_takeover(SessionRegistry, session_id, "client-b", reason: "manual override")

IO.puts("takeover_owner=#{takeover.owner} previous_owner=#{takeover.previous_owner}")

:ok = SessionRegistry.release_lock(SessionRegistry, session_id, takeover.lock_token)
IO.puts("lock_released=true")
