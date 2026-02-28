defmodule Jido.Document.Phase5DesktopAdapterIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Document.Adapters.{DesktopCoordinator, DesktopIPC}
  alias Jido.Document.{SessionRegistry, SessionSupervisor, SignalBus}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))

    signal_bus_name = String.to_atom("phase5_desktop_signal_bus_" <> uniq)
    supervisor_name = String.to_atom("phase5_desktop_session_supervisor_" <> uniq)
    registry_name = String.to_atom("phase5_desktop_session_registry_" <> uniq)
    coordinator_name = String.to_atom("phase5_desktop_coordinator_" <> uniq)

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

    start_supervised!(
      {DesktopCoordinator,
       name: coordinator_name,
       registry: registry_name,
       signal_bus: signal_bus_name,
       max_replay_events: 32}
    )

    tmp_dir = Path.join(File.cwd!(), "tmp_jido_document_phase5_desktop_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Desktop\"\n---\nBody\n")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{coordinator: coordinator_name, path: source_path}
  end

  test "defines IPC request/response contracts and supports replay on reconnect", ctx do
    assert {:ok, window} =
             DesktopCoordinator.register_window(
               ctx.coordinator,
               "window-a",
               %{mode: :shared, path: ctx.path}
             )

    request = %{
      "type" => "action.request",
      "request_id" => "req-1",
      "action" => "update_body",
      "session_id" => window.session_id,
      "params" => %{"body" => "Desktop Updated\n"}
    }

    assert {:ok, decoded} = DesktopIPC.decode_request(request)
    assert decoded.action == :update_body

    assert {:ok, response} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-a", request)

    assert response["type"] == "action.response"
    assert response["status"] == "ok"
    assert response["action"] == "update_body"

    assert {:ok, events} = DesktopCoordinator.drain_outbox(ctx.coordinator, "window-a")
    assert Enum.any?(events, fn event -> event["type"] == "session.signal" end)
    assert Enum.any?(events, fn event -> event["revision"] == 1 end)

    assert :ok = DesktopCoordinator.disconnect_window(ctx.coordinator, "window-a")

    assert {:ok, reconnect} =
             DesktopCoordinator.reconnect_window(
               ctx.coordinator,
               "window-a",
               since_revision: 0
             )

    assert reconnect.window.connected == true
    assert Enum.any?(reconnect.replay, fn event -> event["event"] == "updated" end)
  end

  test "coordinates shared/isolated windows and emits conflict prompts", ctx do
    assert {:ok, win_a} =
             DesktopCoordinator.register_window(
               ctx.coordinator,
               "window-a",
               %{mode: :shared, path: ctx.path}
             )

    assert {:ok, win_b} =
             DesktopCoordinator.register_window(
               ctx.coordinator,
               "window-b",
               %{mode: :shared, path: ctx.path}
             )

    assert {:ok, win_c} =
             DesktopCoordinator.register_window(
               ctx.coordinator,
               "window-c",
               %{mode: :isolated, path: ctx.path}
             )

    assert win_a.session_id == win_b.session_id
    refute win_a.session_id == win_c.session_id

    request_a = %{
      "type" => "action.request",
      "request_id" => "req-shared-a",
      "action" => "update_body",
      "session_id" => win_a.session_id,
      "params" => %{"body" => "Window A owns lock\n"}
    }

    assert {:ok, ok_response} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-a", request_a)

    assert ok_response["status"] == "ok"

    request_b = %{
      "type" => "action.request",
      "request_id" => "req-shared-b",
      "action" => "update_body",
      "session_id" => win_b.session_id,
      "params" => %{"body" => "Window B conflict\n"}
    }

    assert {:ok, conflict_response} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-b", request_b)

    assert conflict_response["status"] == "error"
    assert conflict_response["error"][:code] == :conflict

    assert {:ok, win_b_events} = DesktopCoordinator.drain_outbox(ctx.coordinator, "window-b")
    assert Enum.any?(win_b_events, fn event -> event["type"] == "editor.conflict_prompt" end)

    assert Enum.any?(win_b_events, fn event ->
             event["type"] == "session.signal" and
               get_in(event, ["data", "action"]) == :lock_state
           end)
  end
end
