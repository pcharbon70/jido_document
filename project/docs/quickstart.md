# Quickstart

This guide shows the minimal setup to run a document session lifecycle.

## 1. Create a Mix project and dependency

```bash
mix new demo_doc
cd demo_doc
```

Add dependency in `mix.exs`:

```elixir
defp deps do
  [
    {:jido_document, "~> 0.1"}
  ]
end
```

Install dependencies:

```bash
mix deps.get
```

## 2. Run a session lifecycle

Create `demo.exs`:

```elixir
Application.ensure_all_started(:jido_document)

{:ok, agent} = Jido.Document.start_session(session_id: "quickstart")

path = Path.join(System.tmp_dir!(), "quickstart.md")
File.write!(path, "---\ntitle: \"Quickstart\"\n---\nHello\n")

load_opts = [context_options: %{workspace_root: "/"}]

Jido.Document.Agent.command(agent, :load, %{path: path}, load_opts)
Jido.Document.Agent.command(agent, :update_body, %{body: "Updated body\n"})
Jido.Document.Agent.command(agent, :render, %{})
Jido.Document.Agent.command(agent, :save, %{path: path}, load_opts)
```

Run it:

```bash
mix run demo.exs
```

## 3. Validate API contract before release

```bash
mix jido.api_manifest --check
mix test
```
