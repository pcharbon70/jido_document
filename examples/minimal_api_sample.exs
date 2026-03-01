Application.ensure_all_started(:jido_document)

alias Jido.Document.Agent

session_id = "example-minimal-" <> Integer.to_string(System.unique_integer([:positive]))
{:ok, agent} = Agent.start_link(session_id: session_id)

tmp_dir = Path.join(System.tmp_dir!(), "jido_document_example_minimal_" <> session_id)
File.mkdir_p!(tmp_dir)

path = Path.join(tmp_dir, "document.md")
File.write!(path, "---\ntitle: \"Minimal\"\n---\nBody\n")

load_opts = [context_options: %{workspace_root: "/"}]

{:ok, load_value, _} =
  Agent.command(agent, :load, %{path: path}, load_opts)
  |> Jido.Document.Action.Result.unwrap()

{:ok, _update_value, _} =
  Agent.command(agent, :update_body, %{body: "Updated body\n"})
  |> Jido.Document.Action.Result.unwrap()

{:ok, render_value, _} =
  Agent.command(agent, :render, %{})
  |> Jido.Document.Action.Result.unwrap()

{:ok, save_value, _} =
  Agent.command(agent, :save, %{path: path}, load_opts)
  |> Jido.Document.Action.Result.unwrap()

IO.puts("session_id=#{session_id}")
IO.puts("loaded_path=#{load_value.path}")
IO.puts("preview_toc=#{length(render_value.preview.toc)}")
IO.puts("saved_bytes=#{save_value.bytes}")

if Process.alive?(agent), do: GenServer.stop(agent, :normal)
File.rm_rf(tmp_dir)
