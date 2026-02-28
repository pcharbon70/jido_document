This is a great architectural challenge. By leveraging the **Jido** ecosystem, we can create a robust, agent-oriented architecture where the document itself is a managed entity. This fits perfectly with the requirement for multiple interfaces (LiveView, TUI, Desktop) controlling the same underlying logic.

Here is the proposed architecture for the library, which we will call **`JidoDocs`**.

---

### 1. High-Level Architecture

The core philosophy is **"Agent as the Document Session."**
Instead of a passive data structure, an editing session is an active Agent (using `Jido`). This agent holds the state, validates changes, and coordinates persistence.

The architecture consists of three layers:
1.  **Core Layer (`JidoDocs`)**: Pure data structures, parsing, and serialization logic. UI-agnostic.
2.  **Action Layer (`JidoActions`)**: Atomic, reusable operations (Load, Save, Update) that interact with the file system or external APIs.
3.  **Agent Layer (`JidoDocs.Agent`)**: The stateful process that orchestrates actions, manages undo/redo history, and broadcasts updates to UIs via Signals.

### 2. Core Layer: Data & Parsing

We need a structured representation of a file that contains FrontMatter and Markdown.

#### The Document Struct
We define a struct that separates the metadata (FrontMatter) from the content (Body).

```elixir
defmodule JidoDocs.Document do
  @moduledoc """
  Represents a document with FrontMatter and Markdown body.
  """
  defstruct [:path, :frontmatter, :body, :raw, :schema, dirty: false]

  @type t :: %__MODULE__{
    path: Path.t(),
    frontmatter: map(),
    body: String.t(),
    raw: String.t(),
    schema: module() | nil,
    dirty: boolean()
  }

  @doc """
  Parses raw file content into a Document struct.
  Handles the splitting of FrontMatter (YAML/TOML) and Markdown.
  """
  def parse(raw_content, opts \\ []) do
    # Split content based on --- or +++ delimiters
    {fm_string, body} = split_frontmatter(raw_content)
    
    # Parse Frontmatter (implementation detail depends on YAML/TOML lib)
    {:ok, frontmatter} = parse_frontmatter(fm_string, opts[:syntax])
    
    {:ok, %__MODULE__{
      raw: raw_content,
      frontmatter: frontmatter,
      body: body,
      schema: opts[:schema]
    }}
  end

  @doc """
  Serializes the Document struct back to string for saving.
  """
  def serialize(%__MODULE__{} = doc) do
    fm_serialized = serialize_frontmatter(doc.frontmatter)
    "---\n#{fm_serialized}\n---\n#{doc.body}"
  end
end
```

#### FrontMatter Schema
To support the "Form Section" in the UI, we need a schema definition. This allows the UI to dynamically generate fields (text input, dropdowns, checkboxes).

```elixir
defmodule JidoDocs.Schema do
  @callback fields() :: [JidoDocs.Field.t()]
  
  # Example implementation by the user
  defmodule MyBlogSchema do
    @behaviour JidoDocs.Schema
    
    def fields do
      [
        %JidoDocs.Field{name: :title, type: :string, label: "Post Title"},
        %JidoDocs.Field{name: :tags, type: {:array, :string}},
        %JidoDocs.Field{name: :published, type: :boolean, default: false}
      ]
    end
  end
end
```

### 3. Jido Integration: Actions & Signals

We utilize `JidoAction` for the verbs and `JidoSignal` for eventing.

#### Actions (Verbs)
These are the atomic operations that the Agent will execute.

1.  **`JidoDocs.Actions.Load`**:
    *   Input: `path`, `schema`.
    *   Logic: Reads file from disk, calls `Document.parse/2`.
    *   Output: `%Document{}`.

2.  **`JidoDocs.Actions.Save`**:
    *   Input: `document`.
    *   Logic: Calls `Document.serialize/1`, writes to disk.
    *   Output: `{:ok, path}`.

3.  **`JidoDocs.Actions.Render`**:
    *   Input: `document`.
    *   Logic: Uses `Mdex` to render the body to HTML/AST.
    *   Output: `%{html: ..., toc: ...}`.

#### Signals (Events)
When the document changes, the Agent emits signals that UIs subscribe to.

*   `jido_docs/document/loaded`
*   `jido_docs/document/updated` (payload contains changes)
*   `jido_docs/document/saved`

### 4. The Agent: Stateful Session

This is where the magic happens. We create a `Jido.Agent` to represent the editor session.

```elixir
defmodule JidoDocs.Agent do
  use Jido.Agent,
    name: "jido_docs_session",
    actions: [
      JidoDocs.Actions.Load,
      JidoDocs.Actions.Save,
      JidoDocs.Actions.Render
    ]

  # The Agent State
  defstruct [:document, :preview, :history]

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{document: nil, history: []}}
  end

  @impl true
  def handle_signal(%JidoSignal{type: "jido_docs/document/loaded", data: doc}, state) do
    # When loaded, we might automatically render a preview
    {:noreply, %{state | document: doc}}
  end
  
  @impl true
  def handle_action(:update_frontmatter, params, state) do
    # Direct manipulation of state
    new_doc = %{state.document | frontmatter: params.data, dirty: true}
    
    # Emit signal that UIs should listen to
    signal = JidoSignal.new!(type: "jido_docs/document/updated", data: new_doc)
    
    {:ok, signal, %{state | document: new_doc}}
  end
  
  @impl true
  def handle_action(:update_body, params, state) do
    new_doc = %{state.document | body: params.body, dirty: true}
    
    # Optimization: We could use Mdex here to render just the diff or new HTML
    # if we want real-time preview in the agent state.
    
    signal = JidoSignal.new!(type: "jido_docs/document/updated", data: new_doc)
    {:ok, signal, %{state | document: new_doc}}
  end
end
```

### 5. Markdown & Mdex Integration

Since you are building a coding assistant, `Mdex` is the perfect choice because it wraps `comrak` (Rust implementation), offering high performance for real-time editing.

We should use **Mdex Plugins** to handle the specific needs of a coding assistant:

*   **Syntax Highlighting**: Use `mdex_syntax_highlight` plugin for code blocks.
*   **FrontMatter Extraction**: While `mdex` parses frontmatter, we often need to strip it before rendering the HTML preview (as the UI renders the FrontMatter separately as a Form).

**Rendering Pipeline:**

```elixir
defmodule JidoDocs.Renderer do
  alias Mdex.{Document, Pipe}

  def to_html(body) do
    Document.new(body)
    |> Pipe.new()
    # Ensure standard markdown rendering
    |> Pipe.default() 
    # Add syntax highlighting for code blocks
    |> Pipe.put(:syntax_highlight, theme: "onedark") 
    # Render to HTML
    |> Pipe.to_html()
  end
end
```

### 6. UI Integration Strategy (LiveView Example)

The LiveView interface doesn't hold the logic; it just holds the form state and communicates with the Agent.

1.  **Mount**: The LiveView starts or connects to a `JidoDocs.Agent` process (identified by a session ID or file path).
2.  **Subscribe**: The LiveView subscribes to the Agent's signals (`jido_docs/document/updated`).
3.  **Form Interaction**:
    *   User types in the "Title" field (FrontMatter).
    *   LiveView sends a `cmd/3` to the Agent: `update_frontmatter(%{title: "New Title"})`.
    *   Agent validates, updates state, broadcasts Signal.
    *   LiveView receives Signal, updates assigns.
4.  **Markdown Editing**:
    *   User types in the textarea.
    *   LiveView sends `update_body(text)`.
    *   Agent updates state.
    *   **Async Preview**: The Agent (or a separate Action) runs `Mdex` to render HTML and emits a signal with the preview HTML.

### 7. Summary of Dependencies

*   **`Jido`**: Core agent behavior and supervision.
*   **`JidoSignal`**: Event bus for UI synchronization.
*   **`JidoAction`**: Atomic file operations and parsing.
*   **`Mdex`**: Markdown parsing and rendering.
*   **`YamlElixir` / `Toml`**: For parsing the FrontMatter specifically (as Mdex usually parses it into a string or basic map, we may want deeper schema validation).

This architecture cleanly separates the "What" (Document Struct) from the "How" (Actions) and the "State" (Agent), making it trivial to plug in a TUI (Terminal User Interface) or Desktop client later—simply swap the Signal listener/adapter.