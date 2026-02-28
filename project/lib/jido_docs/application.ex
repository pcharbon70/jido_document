defmodule JidoDocs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [JidoDocs.SessionRegistry]
    opts = [strategy: :one_for_one, name: JidoDocs.Supervisor]

    with {:ok, config} <- JidoDocs.Config.load(),
         {:ok, pid} <- Supervisor.start_link(children, opts) do
      JidoDocs.Diagnostics.emit(
        [:jido_docs, :application, :started],
        %{system_time: System.system_time()},
        %{
          children: length(children),
          workspace_root: config.workspace_root
        }
      )

      {:ok, pid}
    else
      {:error, errors} when is_list(errors) ->
        {:error, {:invalid_config, errors}}
    end
  end
end
