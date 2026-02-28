defmodule JidoDocs.Actions.Save do
  @moduledoc """
  Action boundary for persisting a document.
  """

  @spec run(map()) :: {:error, :not_implemented}
  def run(_params), do: {:error, :not_implemented}
end
