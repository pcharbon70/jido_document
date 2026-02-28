defmodule JidoDocs.Diagnostics do
  @moduledoc """
  Lightweight diagnostics event emitter used during startup and runtime hooks.
  """

  require Logger

  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) when is_list(event) do
    Logger.debug("jido_docs event=#{Enum.join(Enum.map(event, &to_string/1), ".")}")

    if Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :execute, 3) do
      apply(:telemetry, :execute, [event, measurements, metadata])
    end

    :ok
  rescue
    _ -> :ok
  end
end
