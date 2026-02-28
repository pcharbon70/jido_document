defmodule JidoDocs do
  @moduledoc """
  Public entrypoint for JidoDocs core domain modules.
  """

  @type result(value) :: {:ok, value} | {:error, term()}

  @spec start_session(keyword()) :: GenServer.on_start()
  def start_session(opts \\ []) do
    JidoDocs.Agent.start_link(opts)
  end
end
