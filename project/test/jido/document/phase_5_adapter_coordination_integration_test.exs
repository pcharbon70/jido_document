defmodule Jido.Document.Phase5AdapterCoordinationIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Document.Adapters.{DesktopCoordinator, LiveView, TUI}
  alias Jido.Document.Field
  alias Jido.Document.{SessionRegistry, SessionSupervisor, Signal, SignalBus}

  defmodule CoordinationSchema do
    @behaviour Jido.Document.Schema

    @impl true
    def fields do
      [
        %Field{name: :title, type: :string, required: true},
        %Field{name: :published, type: :boolean, default: false}
      ]
    end
  end

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))

    signal_bus_name = String.to_atom("phase5_coord_signal_bus_" <> uniq)
    supervisor_name = String.to_atom("phase5_coord_session_supervisor_" <> uniq)
    registry_name = String.to_atom("phase5_coord_session_registry_" <> uniq)
    coordinator_name = String.to_atom("phase5_coord_desktop_coordinator_" <> uniq)

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
       max_replay_events: 64}
    )

    tmp_dir = Path.join(File.cwd!(), "tmp_jido_document_phase5_coord_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Coordination\"\n---\nBody\n")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{
      registry: registry_name,
      signal_bus: signal_bus_name,
      coordinator: coordinator_name,
      path: source_path,
      tmp_dir: tmp_dir
    }
  end

  test "liveview and tui remain consistent while sharing one session", ctx do
    assert {:ok, live} =
             LiveView.mount(
               %{"path" => ctx.path},
               registry: ctx.registry,
               signal_bus: ctx.signal_bus,
               schema: CoordinationSchema
             )

    assert {:ok, tui} =
             TUI.connect(
               %{session_id: live.session_id},
               registry: ctx.registry,
               signal_bus: ctx.signal_bus
             )

    assert live.session_id == tui.session_id

    assert {:ok, tui} = TUI.handle_key(tui, "ctrl+b", %{"body" => "Cross-adapter update\n"})
    updated = await_signal(:updated, live.session_id)
    assert {:noreply, live} = LiveView.handle_info(live, {:jido_document_signal, updated})

    assert live.assigns.revision == tui.status_bar.revision
    assert live.assigns.revision == 1

    assert {:ok, _tui} = TUI.handle_key(tui, "ctrl+r")
    rendered = await_signal(:rendered, live.session_id)
    assert {:noreply, live} = LiveView.handle_info(live, {:jido_document_signal, rendered})
    assert is_map(live.assigns.preview)
  end

  test "desktop shared windows broadcast lock state and conflict prompts", ctx do
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

    assert win_a.session_id == win_b.session_id

    assert {:ok, _response} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-a", %{
               "type" => "action.request",
               "request_id" => "shared-a-1",
               "action" => "update_body",
               "session_id" => win_a.session_id,
               "params" => %{"body" => "Desktop A lock owner\n"}
             })

    assert {:ok, conflict} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-b", %{
               "type" => "action.request",
               "request_id" => "shared-b-1",
               "action" => "update_body",
               "session_id" => win_b.session_id,
               "params" => %{"body" => "Desktop B conflict\n"}
             })

    assert conflict["status"] == "error"

    assert {:ok, outbox_b} = DesktopCoordinator.drain_outbox(ctx.coordinator, "window-b")
    assert Enum.any?(outbox_b, fn event -> event["type"] == "editor.conflict_prompt" end)

    assert Enum.any?(outbox_b, fn event ->
             event["type"] == "session.signal" and
               get_in(event, ["data", "action"]) == :lock_state
           end)

    windows = DesktopCoordinator.list_windows(ctx.coordinator, win_a.session_id)
    assert Enum.map(windows, & &1.window_id) == ["window-a", "window-b"]
  end

  test "stale lock tokens, disconnect recovery, forced takeover, and diagnostics are deterministic",
       ctx do
    assert {:ok, win_a} =
             DesktopCoordinator.register_window(
               ctx.coordinator,
               "window-a",
               %{mode: :shared, path: ctx.path}
             )

    assert {:ok, _ok} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-a", %{
               "type" => "action.request",
               "request_id" => "stale-0",
               "action" => "update_body",
               "session_id" => win_a.session_id,
               "params" => %{"body" => "Initial owner\n"}
             })

    assert {:ok, stale} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-a", %{
               "type" => "action.request",
               "request_id" => "stale-1",
               "action" => "update_body",
               "session_id" => win_a.session_id,
               "lock_token" => "stale-token",
               "params" => %{"body" => "Should conflict\n"}
             })

    assert stale["status"] == "error"
    assert stale["error"][:code] == :conflict

    assert {:ok, tui} =
             TUI.connect(
               %{session_id: win_a.session_id},
               registry: ctx.registry,
               signal_bus: ctx.signal_bus
             )

    disconnected = TUI.disconnect(tui, :transport_drop)
    save_path = Path.join(ctx.tmp_dir, "recovered.md")

    assert {:ok, live} =
             LiveView.mount(
               %{session_id: win_a.session_id},
               registry: ctx.registry,
               signal_bus: ctx.signal_bus,
               schema: CoordinationSchema
             )

    assert {:noreply, live} =
             LiveView.handle_event(live, :body_change, %{"body" => "Recovered body\n"})

    assert {:noreply, live} = LiveView.handle_event(live, :save, %{"path" => save_path})
    assert File.exists?(save_path)

    assert {:ok, recovered} = TUI.reconnect(disconnected)
    assert recovered.panes.editor.body == "Recovered body\n"

    assert {:noreply, invalid_live} =
             LiveView.handle_event(
               live,
               :frontmatter_change,
               %{"changes" => %{"published" => "invalid-boolean"}}
             )

    assert invalid_live.assigns.last_error.code == :validation_failed

    assert {:error, tui_error, _} = TUI.handle_key(recovered, "ctrl+unknown")
    assert tui_error.code == :invalid_params

    assert {:error, bad_request} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-a", %{
               "type" => "action.request",
               "request_id" => "bad-action",
               "action" => "not_supported",
               "session_id" => win_a.session_id
             })

    assert bad_request["status"] == "error"

    assert {:ok, _win_b} =
             DesktopCoordinator.register_window(
               ctx.coordinator,
               "window-b",
               %{mode: :shared, path: ctx.path}
             )

    assert {:ok, takeover} =
             DesktopCoordinator.handle_ipc_request(ctx.coordinator, "window-b", %{
               "type" => "action.request",
               "request_id" => "takeover-1",
               "action" => "force_takeover",
               "session_id" => win_a.session_id,
               "params" => %{"reason" => "window-a stale owner"}
             })

    assert takeover["status"] == "ok"

    assert {:ok, session_info} = SessionRegistry.fetch_session(ctx.registry, win_a.session_id)
    assert session_info.lock_owner == "desktop:window-b"

    assert {:ok, outbox_a} = DesktopCoordinator.drain_outbox(ctx.coordinator, "window-a")

    assert Enum.any?(outbox_a, fn event ->
             event["type"] == "session.signal" and
               get_in(event, ["data", "payload", "action"]) == :takeover
           end)
  end

  defp await_signal(type, session_id) do
    receive do
      {:jido_document_signal, %Signal{type: ^type, session_id: ^session_id} = signal} ->
        signal

      {:jido_document_signal, _other} ->
        await_signal(type, session_id)
    after
      1_000 -> flunk("expected #{inspect(type)} signal for #{session_id}")
    end
  end
end
