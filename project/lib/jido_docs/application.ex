defmodule JidoDocs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {JidoDocs.Render.Metrics, name: JidoDocs.Render.Metrics},
      {JidoDocs.Render.JobQueue, name: JidoDocs.Render.JobQueue},
      {JidoDocs.SignalBus, name: JidoDocs.SignalBus}
    ]

    opts = [strategy: :one_for_one, name: JidoDocs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
