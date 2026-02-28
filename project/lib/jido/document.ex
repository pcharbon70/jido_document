defmodule Jido.Document do
  @moduledoc """
  Public entrypoint for Jido.Document core domain modules.
  """

  @type result(value) :: {:ok, value} | {:error, term()}

  @spec start_session(keyword()) :: GenServer.on_start()
  def start_session(opts \\ []) do
    Jido.Document.Agent.start_link(opts)
  end
end
