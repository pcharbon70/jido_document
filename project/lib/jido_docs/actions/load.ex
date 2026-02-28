defmodule JidoDocs.Actions.Load do
  @moduledoc """
  Action boundary for loading a document into a session.
  """

  @spec run(map()) :: {:error, :not_implemented}
  def run(_params), do: {:error, :not_implemented}
end
