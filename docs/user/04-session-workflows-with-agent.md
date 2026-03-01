# 04 - Session Workflows with Agent

This guide moves from pure document functions to stateful session orchestration.

## Components in this guide

- `Jido.Document.Agent`
- `Jido.Document.Action.Result`
- `Jido.Document.Signal`

## 1. Start a session

```elixir
Application.ensure_all_started(:jido_document)
{:ok, agent} = Jido.Document.Agent.start_link(session_id: "user-guide-04")
```

## 2. Run action commands

```elixir
alias Jido.Document.Agent
alias Jido.Document.Action.Result

workspace_root = Path.expand(".")
path = Path.join(workspace_root, "tmp/agent_flow.md")

File.mkdir_p!(Path.dirname(path))
File.write!(path, "---\ntitle: \"Agent Flow\"\n---\nBody\n")

opts = [context_options: %{workspace_root: workspace_root}]

{:ok, loaded, _} =
  Agent.command(agent, :load, %{path: path}, opts)
  |> Result.unwrap()

{:ok, _updated, _} =
  Agent.command(agent, :update_frontmatter, %{changes: %{owner: "docs"}})
  |> Result.unwrap()

{:ok, rendered, _} =
  Agent.command(agent, :render, %{})
  |> Result.unwrap()

{:ok, saved, _} =
  Agent.command(agent, :save, %{path: loaded.path}, opts)
  |> Result.unwrap()

IO.puts("toc entries: #{length(rendered.preview.toc)}")
IO.puts("saved revision: #{saved.revision}")
```

Supported action names:

- `:load`
- `:save`
- `:update_frontmatter`
- `:update_body`
- `:render`
- `:undo`
- `:redo`

## 3. Sync and async command modes

```elixir
# default: synchronous call
result = Agent.command(agent, :update_body, %{body: "Sync edit\n"})

# async fire-and-forget
:ok = Agent.command(agent, :update_body, %{body: "Async edit\n"}, mode: :async)
```

## 4. Subscribe to session signals

```elixir
:ok = Agent.subscribe(agent)

receive do
  {:jido_document_signal, signal} ->
    IO.inspect(signal.type, label: "signal")
after
  1_000 -> :ok
end
```

## 5. Inspect session state

```elixir
state = Agent.state(agent)
IO.inspect(state.document.revision, label: "current revision")
```

## Next

Continue with [05 - Rendering and Preview Pipeline](./05-rendering-and-preview-pipeline.md).

