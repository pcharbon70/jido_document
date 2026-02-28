defmodule JidoDocs.Agent do
  @moduledoc """
  Stateful session process that owns the active document state.

  In Phase 1 this module provides a minimal compile-safe process and
  a stable state shape for follow-up phases.
  """

  use GenServer

  alias JidoDocs.Document

  @type state :: %__MODULE__{
          document: Document.t() | nil,
          preview: map() | nil,
          history: list(),
          subscribers: MapSet.t(pid())
        }

  defstruct document: nil,
            preview: nil,
            history: [],
            subscribers: MapSet.new()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end
end
