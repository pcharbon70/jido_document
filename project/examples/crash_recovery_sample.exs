Application.ensure_all_started(:jido_document)

alias Jido.Document.Agent

session_id = "example-recovery-" <> Integer.to_string(System.unique_integer([:positive]))
tmp_dir = Path.join(System.tmp_dir!(), "jido_document_example_recovery_" <> session_id)
checkpoint_dir = Path.join(tmp_dir, "checkpoints")

File.mkdir_p!(checkpoint_dir)

path = Path.join(tmp_dir, "document.md")
File.write!(path, "---\ntitle: \"Recovery\"\n---\nBody\n")

opts = [checkpoint_dir: checkpoint_dir, checkpoint_on_edit: true, autosave_interval_ms: nil]
load_opts = [context_options: %{workspace_root: "/"}]

{:ok, agent} = Agent.start_link(Keyword.put(opts, :session_id, session_id))
%{status: :ok} = Agent.command(agent, :load, %{path: path}, load_opts)
%{status: :ok} = Agent.command(agent, :update_body, %{body: "Unsaved change\n"})

Process.unlink(agent)
Process.exit(agent, :kill)
Process.sleep(25)

{:ok, restarted} = Agent.start_link(Keyword.put(opts, :session_id, session_id))
pending = Agent.recovery_status(restarted)

IO.puts("recovery_pending=#{pending != nil}")

case Agent.recover(restarted) do
  %{status: :ok, value: %{document: document}} ->
    IO.puts("recovered_body=#{String.trim(document.body)}")

  %{status: :error, error: error} ->
    IO.puts("recovery_failed=#{error.code}")
end

if Process.alive?(restarted), do: GenServer.stop(restarted, :normal)
File.rm_rf(tmp_dir)
