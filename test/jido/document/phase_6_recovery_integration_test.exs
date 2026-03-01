defmodule Jido.Document.Phase6RecoveryIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, Checkpoint}

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    session_id = "phase6-recovery-" <> uniq

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase6_recovery_" <> uniq)
    File.mkdir_p!(tmp_dir)

    checkpoint_dir = Path.join(tmp_dir, "checkpoints")
    File.mkdir_p!(checkpoint_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Recovery\"\n---\nBody 0\n")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{
      session_id: session_id,
      tmp_dir: tmp_dir,
      checkpoint_dir: checkpoint_dir,
      source_path: source_path
    }
  end

  test "restores unsaved edits from checkpoint after restart", ctx do
    {:ok, agent} = start_agent(ctx.session_id, ctx.checkpoint_dir)

    assert %{status: :ok} = Agent.command(agent, :load, %{path: ctx.source_path}, fs_opts())
    assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "Unsaved body\n"})

    checkpoint_path = Checkpoint.checkpoint_path(ctx.session_id, dir: ctx.checkpoint_dir)
    assert File.exists?(checkpoint_path)

    :ok = GenServer.stop(agent, :normal)

    {:ok, restarted} = start_agent(ctx.session_id, ctx.checkpoint_dir)

    pending = Agent.recovery_status(restarted)
    assert pending != nil
    assert pending.document.body == "Unsaved body\n"

    assert %{status: :ok, value: value} = Agent.recover(restarted)
    assert value.recovered == true
    assert value.document.body == "Unsaved body\n"
    refute File.exists?(checkpoint_path)

    state = Agent.state(restarted)
    assert state.document.body == "Unsaved body\n"
    assert Agent.recovery_status(restarted) == nil

    :ok = GenServer.stop(restarted, :normal)
  end

  test "recovery requires explicit force when disk content diverged", ctx do
    {:ok, agent} = start_agent(ctx.session_id, ctx.checkpoint_dir)

    assert %{status: :ok} = Agent.command(agent, :load, %{path: ctx.source_path}, fs_opts())
    assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "Checkpoint body\n"})

    :ok = GenServer.stop(agent, :normal)

    File.write!(ctx.source_path, "---\ntitle: \"Recovery\"\n---\nChanged externally\n")

    {:ok, restarted} = start_agent(ctx.session_id, ctx.checkpoint_dir)

    assert %{status: :error, error: error} = Agent.recover(restarted)
    assert error.code == :conflict
    assert error.details.remediation == [:force_recover, :discard, :reload]

    assert %{status: :ok, value: value} = Agent.recover(restarted, force: true)
    assert value.document.body == "Checkpoint body\n"
    assert String.contains?(File.read!(ctx.source_path), "Changed externally")

    :ok = GenServer.stop(restarted, :normal)
  end

  test "lists orphan checkpoint candidates and supports discard", ctx do
    {:ok, agent} = start_agent(ctx.session_id, ctx.checkpoint_dir)
    assert %{status: :ok} = Agent.command(agent, :load, %{path: ctx.source_path}, fs_opts())
    assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "Orphan body\n"})
    :ok = GenServer.stop(agent, :normal)

    assert {:ok, candidates} = Agent.list_recovery_candidates(checkpoint_dir: ctx.checkpoint_dir)
    assert Enum.any?(candidates, &(&1.session_id == ctx.session_id))

    {:ok, restarted} = start_agent(ctx.session_id, ctx.checkpoint_dir)
    assert Agent.recovery_status(restarted) != nil

    assert %{status: :ok, value: %{discarded: true}} = Agent.discard_recovery(restarted)
    assert Agent.recovery_status(restarted) == nil

    checkpoint_path = Checkpoint.checkpoint_path(ctx.session_id, dir: ctx.checkpoint_dir)
    refute File.exists?(checkpoint_path)

    :ok = GenServer.stop(restarted, :normal)
  end

  defp start_agent(session_id, checkpoint_dir) do
    Agent.start_link(
      session_id: session_id,
      checkpoint_dir: checkpoint_dir,
      checkpoint_on_edit: true,
      autosave_interval_ms: nil
    )
  end

  defp fs_opts, do: [context_options: %{workspace_root: "/"}]
end
