defmodule JidoDocs do
  @moduledoc """
  Public facade for session-oriented document editing.

  The facade stays intentionally small in Phase 1 while the internal
  modules and contracts are established.
  """

  @type result(value) :: {:ok, value} | {:error, term()}

  @spec start_session(keyword()) :: result(pid())
  def start_session(opts \\ []) do
    JidoDocs.Agent.start_link(opts)
  end
end
