defmodule Jido.Document.Phase3SessionLifecycleIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, Signal}

  setup do
    session_id = "phase3-lifecycle-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)
    :ok = Agent.subscribe(agent)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase3_lifecycle_" <> session_id)
    :ok = File.mkdir_p(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    :ok = File.write(source_path, "---\ntitle: \"Base\"\n---\nBody\n")

    fs_opts = [context_options: %{workspace_root: "/"}]
    assert %{status: :ok} = Agent.command(agent, :load, %{path: source_path}, fs_opts)
    assert_receive {:jido_document_signal, %Signal{type: :loaded, session_id: ^session_id}}, 500

    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent, :normal)
      File.rm_rf(tmp_dir)
    end)

    %{
      agent: agent,
      session_id: session_id,
      tmp_dir: tmp_dir,
      source_path: source_path,
      fs_opts: fs_opts
    }
  end

  test "concurrent frontmatter/body updates preserve revision integrity", ctx do
    tasks =
      for idx <- 1..10 do
        Task.async(fn ->
          if rem(idx, 2) == 0 do
            Agent.command(ctx.agent, :update_frontmatter, %{
              changes: %{String.to_atom("k#{idx}") => idx}
            })
          else
            Agent.command(ctx.agent, :update_body, %{body: "Body #{idx}\n"})
          end
        end)
      end

    results = Task.await_many(tasks, 2_000)

    assert Enum.all?(results, &(&1.status == :ok))

    state = Agent.state(ctx.agent)
    assert state.document.revision == 10
    assert state.document.dirty == true
  end

  test "save/render sequences do not leave stale preview state", ctx do
    assert :ok = Agent.command(ctx.agent, :render, %{}, mode: :async)
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: "Latest body\n"})
    assert %{status: :ok} = Agent.command(ctx.agent, :render, %{})

    state = Agent.state(ctx.agent)
    assert state.preview != nil
    assert state.document.revision == 1
    assert String.contains?(state.preview.html, "Latest body")
  end

  test "agent restart supports graceful session close and relaunch", ctx do
    session_id = ctx.session_id

    assert Process.alive?(ctx.agent)

    :ok = GenServer.stop(ctx.agent, :normal)

    assert_receive {:jido_document_signal,
                    %Signal{type: :session_closed, session_id: ^session_id}},
                   500

    {:ok, restarted} = Agent.start_link(session_id: session_id)
    :ok = Agent.subscribe(restarted)

    assert %{status: :ok} = Agent.command(restarted, :load, %{path: ctx.source_path}, ctx.fs_opts)
    assert_receive {:jido_document_signal, %Signal{type: :loaded, session_id: ^session_id}}, 500

    GenServer.stop(restarted, :normal)
  end
end
