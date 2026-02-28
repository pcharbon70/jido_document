defmodule Jido.Document.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    run_plugin_startup_checks()

    children = [
      {Jido.Document.Render.Metrics, name: Jido.Document.Render.Metrics},
      {Jido.Document.Render.JobQueue, name: Jido.Document.Render.JobQueue},
      {Jido.Document.SignalBus, name: Jido.Document.SignalBus},
      {Jido.Document.SessionSupervisor, name: Jido.Document.SessionSupervisor},
      {Jido.Document.SessionRegistry,
       name: Jido.Document.SessionRegistry,
       session_supervisor: Jido.Document.SessionSupervisor,
       signal_bus: Jido.Document.SignalBus}
    ]

    opts = [strategy: :one_for_one, name: Jido.Document.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp run_plugin_startup_checks do
    plugins = Application.get_env(:jido_document, :render_plugins, [])

    context = %{environment: Application.get_env(:jido_document, :runtime_env, :dev)}

    {:ok, _compatible, diagnostics} =
      Jido.Document.Render.PluginManager.startup_check(plugins, context)

    Enum.each(diagnostics, fn diag ->
      Logger.warning("render plugin check: #{diag.message} #{inspect(diag.location)}")
    end)
  end
end
