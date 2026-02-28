defmodule Jido.Document.Phase5LiveViewAdapterIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Document.Adapters.LiveView
  alias Jido.Document.Field
  alias Jido.Document.{SessionRegistry, SessionSupervisor, SignalBus}

  defmodule AdapterSchema do
    @behaviour Jido.Document.Schema

    @impl true
    def fields do
      [
        %Field{name: :title, type: :string, required: true},
        %Field{name: :published, type: :boolean, default: false},
        %Field{name: :tags, type: {:array, :string}, default: []},
        %Field{
          name: :status,
          type: {:enum, ["draft", "published"]},
          options: ["draft", "published"],
          default: "draft"
        }
      ]
    end
  end

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))

    signal_bus_name = String.to_atom("phase5_liveview_signal_bus_" <> uniq)
    supervisor_name = String.to_atom("phase5_liveview_session_supervisor_" <> uniq)
    registry_name = String.to_atom("phase5_liveview_session_registry_" <> uniq)

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

    tmp_dir = Path.join(File.cwd!(), "tmp_jido_document_phase5_liveview_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Hello\"\nstatus: \"draft\"\n---\nBody\n")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{registry: registry_name, signal_bus: signal_bus_name, tmp_dir: tmp_dir, path: source_path}
  end

  test "mounts by path, updates via events, and maps lock signals into assigns", ctx do
    assert {:ok, adapter} =
             LiveView.mount(%{"path" => ctx.path},
               registry: ctx.registry,
               signal_bus: ctx.signal_bus,
               schema: AdapterSchema
             )

    assert adapter.assigns.document.path == Path.expand(ctx.path)
    assert adapter.assigns.save_state == :idle
    assert Process.alive?(adapter.session_pid)

    components =
      adapter.assigns.frontmatter_form.fields
      |> Enum.map(fn field -> {field.name, field.component} end)
      |> Map.new()

    assert components.published == :checkbox
    assert components.tags == :tag_input
    assert components.status == :select

    assert {:noreply, adapter} =
             LiveView.handle_event(adapter, :body_change, %{"body" => "Updated\n"})

    assert adapter.assigns.dirty == true
    assert adapter.assigns.revision == 1

    save_path = Path.join(ctx.tmp_dir, "saved.md")
    assert {:noreply, adapter} = LiveView.handle_event(adapter, :save, %{"path" => save_path})
    assert adapter.assigns.save_state == :saved
    assert adapter.assigns.saving == false
    assert File.exists?(save_path)

    assert {:ok, _signal, _metrics} =
             SignalBus.broadcast(
               ctx.signal_bus,
               :updated,
               adapter.session_id,
               %{action: :lock_state, payload: %{action: :takeover, owner: "desktop-window"}}
             )

    assert_receive {:jido_document_signal, %{data: %{action: :lock_state}} = signal}, 500
    assert {:noreply, adapter} = LiveView.handle_info(adapter, {:jido_document_signal, signal})
    assert adapter.assigns.lock_state.action == :takeover
    assert adapter.assigns.lock_state.owner == "desktop-window"
  end

  test "renders inline validation diagnostics for invalid frontmatter updates", ctx do
    assert {:ok, adapter} =
             LiveView.mount(%{"path" => ctx.path},
               registry: ctx.registry,
               signal_bus: ctx.signal_bus,
               schema: AdapterSchema
             )

    assert {:noreply, invalid} =
             LiveView.handle_event(adapter, :frontmatter_change, %{
               "changes" => %{"published" => "not-bool"}
             })

    assert invalid.assigns.last_error.code == :validation_failed
    assert invalid.assigns.frontmatter_form.errors.published == "must be a boolean"
    assert invalid.assigns.revision == 0

    assert {:noreply, valid} =
             LiveView.handle_event(invalid, :frontmatter_change, %{
               "changes" => %{"status" => "published"}
             })

    assert valid.assigns.last_error == nil
    assert valid.assigns.revision == 1
    assert valid.assigns.dirty == true
  end
end
