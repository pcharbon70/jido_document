defmodule JidoDocs.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    run_plugin_startup_checks()

    children = [
      {JidoDocs.Render.Metrics, name: JidoDocs.Render.Metrics},
      {JidoDocs.Render.JobQueue, name: JidoDocs.Render.JobQueue},
      {JidoDocs.SignalBus, name: JidoDocs.SignalBus},
      {JidoDocs.SessionSupervisor, name: JidoDocs.SessionSupervisor},
      {JidoDocs.SessionRegistry,
       name: JidoDocs.SessionRegistry,
       session_supervisor: JidoDocs.SessionSupervisor,
       signal_bus: JidoDocs.SignalBus}
    ]

    opts = [strategy: :one_for_one, name: JidoDocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp run_plugin_startup_checks do
    plugins = Application.get_env(:project, :render_plugins, [])

    context = %{environment: Application.get_env(:project, :runtime_env, :dev)}

    {:ok, _compatible, diagnostics} =
      JidoDocs.Render.PluginManager.startup_check(plugins, context)

    Enum.each(diagnostics, fn diag ->
      Logger.warning("render plugin check: #{diag.message} #{inspect(diag.location)}")
    end)
  end
end
