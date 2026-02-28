defmodule Jido.Document.Phase6HistoryIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, History, Signal}

  setup do
    session_id = "phase6-history-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id, history_limit: 5)
    :ok = Agent.subscribe(agent)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase6_history_" <> session_id)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Start\"\n---\nBody 0\n")

    fs_opts = [context_options: %{workspace_root: "/"}]

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, session_id: session_id, source_path: source_path, fs_opts: fs_opts}
  end

  test "supports mixed undo/redo chains and clears redo after new edit", ctx do
    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, ctx.fs_opts)

    assert %{status: :ok} =
             Agent.command(ctx.agent, :update_frontmatter, %{changes: %{title: "v1"}})

    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Body 2\n"})

    state = Agent.state(ctx.agent)
    assert History.state(state.history_model).can_undo == true
    assert History.state(state.history_model).undo_depth == 2
    assert History.state(state.history_model).can_redo == false

    assert %{status: :ok, value: %{document: undo1, history: history1}} =
             Agent.command(ctx.agent, :undo, %{})

    assert undo1.body == "Body 0\n"
    assert history1.can_redo == true

    assert %{status: :ok, value: %{document: undo2, history: history2}} =
             Agent.command(ctx.agent, :undo, %{})

    assert undo2.revision == 0
    assert history2.can_undo == false
    assert history2.can_redo == true

    assert %{status: :ok, value: %{document: redo_doc}} = Agent.command(ctx.agent, :redo, %{})
    assert redo_doc.revision == 1

    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Branch body\n"})

    assert %{status: :error, error: error} = Agent.command(ctx.agent, :redo, %{})
    assert error.code == :conflict
    assert error.details.history.can_redo == false
  end

  test "emits history_state signals when undo/redo availability changes", ctx do
    session_id = ctx.session_id

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, ctx.fs_opts)

    assert_receive {:jido_document_signal, %Signal{type: :loaded, session_id: ^session_id}},
                   500

    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Edited once\n"})

    assert_receive {:jido_document_signal,
                    %Signal{
                      type: :updated,
                      session_id: ^session_id,
                      data: %{action: :history_state, payload: payload_after_edit}
                    }},
                   500

    assert payload_after_edit.can_undo == true
    assert payload_after_edit.can_redo == false

    assert %{status: :ok} = Agent.command(ctx.agent, :undo, %{})

    assert_receive {:jido_document_signal,
                    %Signal{
                      type: :updated,
                      session_id: ^session_id,
                      data: %{action: :history_state, payload: payload_after_undo}
                    }},
                   500

    assert payload_after_undo.can_redo == true
  end
end
