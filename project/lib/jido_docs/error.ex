defmodule JidoDocs.Error do
  @moduledoc """
  Normalized error shape for external adapter and dependency failures.
  """

  @type code ::
          :dependency_missing
          | :compatibility_check_failed
          | :parser_unavailable
          | :renderer_unavailable
          | :invalid_input
          | :upstream_error

  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          details: map()
        }

  defstruct [:code, :message, details: %{}]

  @spec new(code(), String.t(), map()) :: t()
  def new(code, message, details \\ %{}) do
    %__MODULE__{code: code, message: message, details: details}
  end

  @spec wrap(code(), term(), map()) :: {:error, t()}
  def wrap(code, reason, details \\ %{}) do
    message = reason_to_message(reason)
    {:error, new(code, message, Map.put(details, :reason, reason))}
  end

  defp reason_to_message(reason) when is_binary(reason), do: reason
  defp reason_to_message(reason), do: inspect(reason)
end
