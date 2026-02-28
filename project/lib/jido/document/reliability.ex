defmodule Jido.Document.Reliability do
  @moduledoc """
  Retry and backoff helpers for transient failures.
  """

  alias Jido.Document.Action.Result
  alias Jido.Document.Error

  @spec with_retry((-> Result.t()), keyword() | map()) :: Result.t()
  def with_retry(fun, opts \\ %{}) when is_function(fun, 0) do
    opts = to_map(opts)
    max_attempts = max(Map.get(opts, :max_attempts, 3), 1)
    base_delay_ms = max(Map.get(opts, :base_delay_ms, 25), 0)
    max_delay_ms = max(Map.get(opts, :max_delay_ms, 1_000), 1)
    jitter_pct = Map.get(opts, :jitter_pct, 0.2)

    do_with_retry(fun, 1, max_attempts, base_delay_ms, max_delay_ms, jitter_pct)
  end

  defp do_with_retry(fun, attempt, max_attempts, base_delay_ms, max_delay_ms, jitter_pct) do
    result = fun.()

    if retryable_result?(result) and attempt < max_attempts do
      delay_ms =
        base_delay_ms
        |> delay_for_attempt(attempt)
        |> min(max_delay_ms)
        |> with_jitter(jitter_pct)

      if delay_ms > 0, do: Process.sleep(delay_ms)
      do_with_retry(fun, attempt + 1, max_attempts, base_delay_ms, max_delay_ms, jitter_pct)
    else
      result
    end
  end

  defp retryable_result?(%Result{status: :error, error: %Error{retryable: true}}), do: true
  defp retryable_result?(_), do: false

  defp delay_for_attempt(base_delay_ms, attempt) do
    base_delay_ms * trunc(:math.pow(2, attempt - 1))
  end

  defp with_jitter(delay_ms, jitter_pct) when is_float(jitter_pct) and jitter_pct > 0 do
    spread = trunc(delay_ms * jitter_pct)
    jitter = Enum.random(-spread..spread)
    max(delay_ms + jitter, 0)
  end

  defp with_jitter(delay_ms, _jitter_pct), do: delay_ms

  defp to_map(%{} = map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(_), do: %{}
end
