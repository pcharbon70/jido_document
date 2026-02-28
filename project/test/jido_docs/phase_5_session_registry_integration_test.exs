defmodule JidoDocs.Phase5SessionRegistryIntegrationTest do
  use ExUnit.Case, async: true

  alias JidoDocs.{SessionRegistry, SessionSupervisor, Signal, SignalBus}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))

    signal_bus_name = String.to_atom("phase5_signal_bus_" <> uniq)
    supervisor_name = String.to_atom("phase5_session_supervisor_" <> uniq)
    registry_name = String.to_atom("phase5_session_registry_" <> uniq)

    start_supervised!({SignalBus, name: signal_bus_name})
    start_supervised!({SessionSupervisor, name: supervisor_name})

    start_supervised!(
      {SessionRegistry,
       name: registry_name,
       signal_bus: signal_bus_name,
       session_supervisor: supervisor_name,
       cleanup_interval_ms: 60_000,
       idle_timeout_ms: 60_000}
    )

    tmp_dir = Path.join(System.tmp_dir!(), "jido_docs_phase5_registry_" <> uniq)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{registry: registry_name, signal_bus: signal_bus_name, tmp_dir: tmp_dir}
  end

  test "ensures deterministic session IDs with explicit and lazy creation", ctx do
    path = Path.join(ctx.tmp_dir, "source.md")
    File.write!(path, "---\ntitle: \"Phase 5\"\n---\nBody\n")

    expected_id = SessionRegistry.session_id_for_path(path)
    assert expected_id == SessionRegistry.session_id_for_path(Path.expand(path))

    assert {:ok, path_session} = SessionRegistry.ensure_session_by_path(ctx.registry, path)
    assert path_session.session_id == expected_id
    assert path_session.path == Path.expand(path)
    assert Process.alive?(path_session.pid)

    assert {:ok, explicit_session} = SessionRegistry.ensure_session(ctx.registry, expected_id)
    assert explicit_session.pid == path_session.pid

    sessions = SessionRegistry.list_sessions(ctx.registry)
    assert Enum.map(sessions, & &1.session_id) == [expected_id]
  end

  test "reclaims stale sessions and terminates their processes", ctx do
    assert {:ok, info} = SessionRegistry.ensure_session(ctx.registry, "ephemeral-session")
    assert Process.alive?(info.pid)
    pid = info.pid

    ref = Process.monitor(pid)
    assert {:ok, removed_ids} = SessionRegistry.reclaim_idle(ctx.registry, 0)
    assert removed_ids == ["ephemeral-session"]
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 500

    assert {:error, error} = SessionRegistry.fetch_session(ctx.registry, "ephemeral-session")
    assert error.code == :not_found
  end

  test "enforces lock ownership, optimistic validation, and administrative takeover", ctx do
    session_id = "lock-session-" <> Integer.to_string(System.unique_integer([:positive]))
    assert {:ok, _info} = SessionRegistry.ensure_session(ctx.registry, session_id)
    assert :ok = SignalBus.subscribe(ctx.signal_bus, session_id, pid: self())

    assert {:ok, lock} = SessionRegistry.acquire_lock(ctx.registry, session_id, "liveview-client")
    assert is_binary(lock.lock_token)
    assert lock.lock_revision == 1
    assert lock.owner == "liveview-client"

    assert_receive {:jido_docs_signal,
                    %Signal{
                      type: :updated,
                      session_id: ^session_id,
                      data: %{action: :lock_state, payload: %{owner: "liveview-client"}}
                    }},
                   500

    assert :ok = SessionRegistry.validate_lock(ctx.registry, session_id, lock.lock_token)

    assert {:error, conflict} = SessionRegistry.acquire_lock(ctx.registry, session_id, "tui-client")
    assert conflict.code == :conflict
    assert conflict.details.owner == "liveview-client"
    assert conflict.details.requested_owner == "tui-client"

    assert {:error, stale} =
             SessionRegistry.acquire_lock(ctx.registry, session_id, "liveview-client",
               expected_token: "stale-token"
             )

    assert stale.code == :conflict
    assert stale.details.expected_token == "stale-token"

    assert {:ok, takeover} =
             SessionRegistry.force_takeover(ctx.registry, session_id, "desktop-client",
               reason: "stuck owner"
             )

    assert takeover.owner == "desktop-client"
    assert takeover.previous_owner == "liveview-client"
    assert takeover.lock_revision == 2
    refute takeover.lock_token == lock.lock_token

    assert_receive {:jido_docs_signal,
                    %Signal{
                      type: :updated,
                      session_id: ^session_id,
                      data: %{action: :lock_state, payload: %{action: :takeover}}
                    }},
                   500

    assert {:error, invalid} = SessionRegistry.release_lock(ctx.registry, session_id, lock.lock_token)
    assert invalid.code == :conflict

    assert :ok = SessionRegistry.release_lock(ctx.registry, session_id, takeover.lock_token)

    assert_receive {:jido_docs_signal,
                    %Signal{
                      type: :updated,
                      session_id: ^session_id,
                      data: %{action: :lock_state, payload: %{action: :released}}
                    }},
                   500
  end
end
