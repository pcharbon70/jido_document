defmodule Jido.Document do
  @moduledoc """
  Public entrypoint for Jido.Document core domain modules.

  Stable API modules:
  - `Jido.Document`
  - `Jido.Document.Agent`
  - `Jido.Document.Document`
  - `Jido.Document.Frontmatter`
  - `Jido.Document.Renderer`
  - `Jido.Document.SchemaMigration`
  - `Jido.Document.SessionRegistry`
  - `Jido.Document.Signal`
  - `Jido.Document.SignalBus`
  """

  @type result(value) :: {:ok, value} | {:error, term()}

  @doc """
  Starts a document session process.

  Options are forwarded to `Jido.Document.Agent.start_link/1`.
  """
  @spec start_session(keyword()) :: GenServer.on_start()
  def start_session(opts \\ []) do
    Jido.Document.Agent.start_link(opts)
  end
end
