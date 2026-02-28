defmodule JidoDocs.Config do
  @moduledoc """
  Runtime configuration contract for JidoDocs.

  Detailed schema and normalization logic are implemented in Section 1.3.
  """

  @type t :: %__MODULE__{
          parser: map(),
          renderer: map(),
          persistence: map(),
          workspace_root: Path.t() | nil
        }

  defstruct parser: %{},
            renderer: %{},
            persistence: %{},
            workspace_root: nil

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end
end
