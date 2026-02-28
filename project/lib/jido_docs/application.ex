defmodule JidoDocs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JidoDocs.SessionRegistry
    ]

    opts = [strategy: :one_for_one, name: JidoDocs.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      JidoDocs.Diagnostics.emit(
        [:jido_docs, :application, :started],
        %{system_time: System.system_time()},
        %{children: length(children)}
      )

      {:ok, pid}
    end
  end
end
