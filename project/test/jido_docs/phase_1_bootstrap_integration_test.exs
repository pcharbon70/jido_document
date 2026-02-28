defmodule JidoDocs.Phase1BootstrapIntegrationTest do
  use ExUnit.Case, async: false

  test "supervision tree boots with baseline defaults" do
    assert Process.whereis(JidoDocs.Supervisor)
    assert Process.whereis(JidoDocs.SessionRegistry)
    assert Process.whereis(JidoDocs.SessionRegistry.Registry)
    assert Process.whereis(JidoDocs.SessionRegistry.SessionSupervisor)
  end

  test "session registry can start and resolve sessions" do
    session_id = "phase1-bootstrap-session"

    assert {:ok, pid} = JidoDocs.SessionRegistry.start_session(session_id)
    assert is_pid(pid)
    assert pid == JidoDocs.SessionRegistry.whereis(session_id)
  end

  test "config precedence and normalization are deterministic" do
    old_app_config = Application.get_env(:project, JidoDocs.Config)

    on_exit(fn ->
      if old_app_config == nil do
        Application.delete_env(:project, JidoDocs.Config)
      else
        Application.put_env(:project, JidoDocs.Config, old_app_config)
      end
    end)

    Application.put_env(:project, JidoDocs.Config,
      renderer: %{debounce_ms: 50},
      persistence: %{backup_extension: ".app"}
    )

    session_opts = [renderer: %{debounce_ms: 80}, persistence: %{temp_dir: "tmp/session"}]

    call_opts = [
      renderer: %{debounce_ms: 100},
      workspace_root: ".",
      persistence: %{temp_dir: "tmp/call"}
    ]

    assert {:ok, config} = JidoDocs.Config.load(call_opts, session_opts)

    assert config.renderer.debounce_ms == 100
    assert config.persistence.backup_extension == ".app"
    assert config.workspace_root == Path.expand(".")
    assert config.persistence.temp_dir == Path.expand("tmp/call", config.workspace_root)
  end

  test "renderer contract falls back safely when primary adapter is unavailable" do
    assert {:ok, rendered} = JidoDocs.Renderer.to_html("# hello")

    assert is_binary(rendered.html)
    assert String.contains?(rendered.html, "hello")
    assert [%{level: :warning} | _] = rendered.diagnostics
  end
end
