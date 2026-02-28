defmodule Jido.Document.Action do
  @moduledoc """
  Standard action behavior and execution harness.

  Actions must declare idempotency expectations so callers can reason about
  safe retries under transient failures.
  """

  alias Jido.Document.Action.{Context, Result}
  alias Jido.Document.Error

  @type idempotency :: :idempotent | :conditionally_idempotent | :non_idempotent

  @callback name() :: atom()
  @callback idempotency() :: idempotency()
  @callback run(params :: map(), context :: Context.t()) :: {:ok, term()} | {:error, term()}

  @spec execute(module(), map() | keyword(), map() | keyword()) :: Result.t()
  def execute(action_module, params, context_attrs) do
    with {:ok, context} <- Context.new(context_attrs) do
      started = System.monotonic_time(:microsecond)
      action_name = action_name(action_module)
      idempotency = action_idempotency(action_module)

      result =
        try do
          action_module.run(normalize_params(params), context)
        rescue
          exception -> {:error, Error.from_exception(exception, %{action: action_name})}
        catch
          kind, reason ->
            {:error,
             Error.new(:internal, "caught #{kind}: #{inspect(reason)}", %{action: action_name})}
        end

      duration_us = System.monotonic_time(:microsecond) - started

      metadata =
        %{
          action: action_name,
          idempotency: idempotency,
          correlation_id: context.correlation_id,
          duration_us: duration_us
        }
        |> maybe_put(:idempotency_key, context.idempotency_key)

      emit_telemetry(result, metadata)

      case result do
        {:ok, value} ->
          Result.ok(value, metadata)

        {:error, %Error{} = error} ->
          Result.error(error, metadata)

        {:error, reason} ->
          Result.error(Error.from_reason(reason, %{action: action_name}), metadata)

        other ->
          Result.error(
            Error.new(:internal, "invalid action return", %{action: action_name, value: other}),
            metadata
          )
      end
    else
      {:error, %Error{} = error} -> Result.error(error, %{action: action_name(action_module)})
    end
  end

  defp action_name(action_module) do
    if function_exported?(action_module, :name, 0), do: action_module.name(), else: action_module
  end

  defp action_idempotency(action_module) do
    if function_exported?(action_module, :idempotency, 0) do
      action_module.idempotency()
    else
      :non_idempotent
    end
  end

  defp normalize_params(%{} = params), do: params
  defp normalize_params(params) when is_list(params), do: Map.new(params)
  defp normalize_params(_), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp emit_telemetry(result, metadata) do
    event =
      case result do
        {:ok, _} -> [:jido_document, :action, :ok]
        _ -> [:jido_document, :action, :error]
      end

    measurements = %{duration_us: Map.get(metadata, :duration_us, 0)}

    if Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :execute, 3) do
      apply(:telemetry, :execute, [event, measurements, metadata])
    end

    :ok
  end
end
