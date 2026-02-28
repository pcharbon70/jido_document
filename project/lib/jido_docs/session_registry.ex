defmodule JidoDocs.SessionRegistry do
  @moduledoc """
  Supervision boundary for session process discovery and lifecycle.
  """

  use Supervisor

  @registry __MODULE__.Registry
  @session_supervisor __MODULE__.SessionSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec via(term()) :: {:via, Registry, {module(), term()}}
  def via(session_id) do
    {:via, Registry, {@registry, session_id}}
  end

  @spec whereis(term()) :: pid() | nil
  def whereis(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @spec start_session(term(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_session(session_id, opts \\ []) do
    child_spec = {JidoDocs.Agent, Keyword.put(opts, :name, via(session_id))}
    DynamicSupervisor.start_child(@session_supervisor, child_spec)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, strategy: :one_for_one, name: @session_supervisor}
    ]

    # `:rest_for_one` preserves registry ordering before session supervision.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
