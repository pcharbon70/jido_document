defmodule JidoDocs.Phase3ActionSignalIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoDocs.{Agent, Signal}

  setup do
    session_id = "phase3-actions-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, agent} = Agent.start_link(session_id: session_id)
    :ok = Agent.subscribe(agent)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_docs_phase3_" <> session_id)
    :ok = File.mkdir_p(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    save_path = Path.join(tmp_dir, "saved.md")

    content = "---\ntitle: \"Test\"\n---\n# Hello\n"
    :ok = File.write(source_path, content)

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, session_id: session_id, source_path: source_path, save_path: save_path}
  end

  test "load/update/render/save emits deterministic signal order", ctx do
    session_id = ctx.session_id
    fs_opts = [context_options: %{workspace_root: "/"}]

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, fs_opts)
    assert_receive {:jido_docs_signal, %Signal{type: loaded, session_id: ^session_id}}, 500

    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "# Updated\n"})
    assert_receive {:jido_docs_signal, %Signal{type: updated, session_id: ^session_id}}, 500

    assert %{status: :ok} = Agent.command(ctx.agent, :render, %{})
    assert_receive {:jido_docs_signal, %Signal{type: rendered, session_id: ^session_id}}, 500

    assert %{status: :ok} = Agent.command(ctx.agent, :save, %{path: ctx.save_path}, fs_opts)
    assert_receive {:jido_docs_signal, %Signal{type: saved, session_id: ^session_id}}, 500

    types = [loaded, updated, rendered, saved]
    assert types == [:loaded, :updated, :rendered, :saved]
  end

  test "failed action emits failed signal with structured diagnostics", ctx do
    session_id = ctx.session_id

    result = Agent.command(ctx.agent, :update_body, %{})
    assert result.status == :error
    assert result.error.code == :invalid_params

    assert_receive {:jido_docs_signal,
                    %Signal{
                      type: :failed,
                      session_id: ^session_id,
                      data: data,
                      schema_version: 1
                    }},
                   500

    assert data.action == :update_body
    assert data.error.code == :invalid_params
    assert is_boolean(data.rollback)
  end

  test "signals always carry current schema version", ctx do
    session_id = ctx.session_id
    fs_opts = [context_options: %{workspace_root: "/"}]

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, fs_opts)
    assert %{status: :ok} = Agent.command(ctx.agent, :render, %{})

    assert_receive {:jido_docs_signal,
                    %Signal{session_id: ^session_id, schema_version: version1}},
                   500

    assert_receive {:jido_docs_signal,
                    %Signal{session_id: ^session_id, schema_version: version2}},
                   500

    assert version1 == 1
    assert version2 == 1
  end
end
