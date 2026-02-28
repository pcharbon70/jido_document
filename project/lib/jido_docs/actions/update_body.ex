defmodule JidoDocs.Actions.UpdateBody do
  @moduledoc """
  Action boundary for markdown body updates.
  """

  @spec run(map()) :: {:error, :not_implemented}
  def run(_params), do: {:error, :not_implemented}
end
