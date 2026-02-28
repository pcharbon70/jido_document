defmodule JidoDocs.Actions.Render do
  @moduledoc """
  Action boundary for generating rendered preview artifacts.
  """

  @spec run(map()) :: {:error, :not_implemented}
  def run(_params), do: {:error, :not_implemented}
end
