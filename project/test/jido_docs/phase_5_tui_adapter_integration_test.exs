defmodule JidoDocs.Phase5TuiAdapterIntegrationTest do
  use ExUnit.Case, async: true

  alias JidoDocs.Adapters.TUI
  alias JidoDocs.{SessionRegistry, SessionSupervisor, Signal, SignalBus}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))

    signal_bus_name = String.to_atom("phase5_tui_signal_bus_" <> uniq)
    supervisor_name = String.to_atom("phase5_tui_session_supervisor_" <> uniq)
    registry_name = String.to_atom("phase5_tui_session_registry_" <> uniq)

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

    tmp_dir = Path.join(File.cwd!(), "tmp_jido_docs_phase5_tui_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"TUI\"\n---\nBody\n")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{registry: registry_name, signal_bus: signal_bus_name, path: source_path, tmp_dir: tmp_dir}
  end

  test "maps keybindings to actions and keeps split-pane state in sync", ctx do
    assert {:ok, adapter} =
             TUI.connect(%{path: ctx.path}, registry: ctx.registry, signal_bus: ctx.signal_bus)

    assert TUI.keymap()["ctrl+s"] == :save
    assert adapter.panes.layout == :split

    assert {:ok, adapter} = TUI.handle_key(adapter, "ctrl+b", %{"body" => "Updated Body\n"})
    assert adapter.panes.editor.body == "Updated Body\n"
    assert adapter.status_bar.revision == 1

    assert {:ok, adapter} = TUI.handle_key(adapter, "ctrl+r")
    assert String.contains?(adapter.panes.preview.html, "Updated Body")

    save_path = Path.join(ctx.tmp_dir, "saved.md")
    assert {:ok, adapter} = TUI.handle_key(adapter, "ctrl+s", %{path: save_path})
    assert adapter.status_bar.save_state == :saving
    assert File.exists?(save_path)

    saved_signal = await_signal(:saved)
    assert %Signal{type: :saved} = saved_signal
    adapter = TUI.handle_signal(adapter, saved_signal)
    assert adapter.status_bar.save_state == :saved

    assert {:ok, _lock} =
             SessionRegistry.acquire_lock(ctx.registry, adapter.session_id, "desktop-window")

    updated_signal = await_signal(:updated)
    assert %Signal{data: %{action: :lock_state}} = updated_signal
    adapter = TUI.handle_signal(adapter, updated_signal)
    assert adapter.status_bar.lock_owner == "desktop-window"
  end

  test "applies redraw throttling, fallback layouts, and reconnect behavior", ctx do
    assert {:ok, adapter} =
             TUI.connect(%{path: ctx.path}, registry: ctx.registry, signal_bus: ctx.signal_bus)

    adapter = TUI.set_viewport(adapter, %{width: 80, height: 20, colors: 8})
    assert adapter.panes.layout == :stacked
    assert adapter.viewport.color_mode == :low

    assert {:ok, frame, adapter} = TUI.render_frame(adapter, now_ms: 1_000, force: true)
    assert frame.layout == :stacked

    assert {:deferred, adapter} = TUI.render_frame(adapter, now_ms: 1_010)
    assert adapter.redraw.pending == true

    assert {:ok, _frame, adapter} = TUI.render_frame(adapter, now_ms: 1_090)
    assert adapter.redraw.pending == false

    adapter = TUI.disconnect(adapter, :transport_lost)
    refute adapter.connected
    assert adapter.status_bar.connected == false

    assert {:error, error, _adapter} = TUI.handle_key(adapter, "ctrl+b", %{body: "noop"})
    assert error.code == :subscription_error

    assert {:ok, reconnected} = TUI.reconnect(adapter)
    assert reconnected.connected
    assert reconnected.status_bar.connected == true
    assert reconnected.status_bar.message == "reconnected"
  end

  defp await_signal(type) do
    receive do
      {:jido_docs_signal, %Signal{type: ^type} = signal} ->
        signal

      {:jido_docs_signal, _signal} ->
        await_signal(type)
    after
      1_000 -> flunk("expected signal #{inspect(type)}")
    end
  end
end
