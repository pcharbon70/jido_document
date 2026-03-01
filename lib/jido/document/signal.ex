defmodule Jido.Document.Signal do
  @moduledoc """
  Versioned signal contract for cross-client session synchronization.
  """

  alias Jido.Document.Error

  @schema_version 1
  @default_max_payload_bytes 16_384

  @known_types [
    :loaded,
    :updated,
    :saved,
    :rendered,
    :failed,
    :session_closed,
    :subscriber_cleaned
  ]

  @type signal_type ::
          :loaded
          | :updated
          | :saved
          | :rendered
          | :failed
          | :session_closed
          | :subscriber_cleaned

  @type t :: %__MODULE__{
          type: signal_type(),
          session_id: String.t(),
          data: map(),
          schema_version: pos_integer(),
          correlation_id: String.t() | nil,
          emitted_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :type,
    :session_id,
    :data,
    :schema_version,
    :correlation_id,
    :emitted_at,
    metadata: %{}
  ]

  @spec known_types() :: [signal_type()]
  def known_types, do: @known_types

  @spec build(signal_type(), String.t(), map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def build(type, session_id, data, opts \\ []) do
    with :ok <- validate_type(type),
         :ok <- validate_session_id(session_id),
         :ok <- validate_data(data) do
      max_payload_bytes = Keyword.get(opts, :max_payload_bytes, @default_max_payload_bytes)
      {normalized_data, truncation_meta} = normalize_data(data, max_payload_bytes)

      {:ok,
       %__MODULE__{
         type: type,
         session_id: session_id,
         data: normalized_data,
         schema_version: Keyword.get(opts, :schema_version, @schema_version),
         correlation_id: Keyword.get(opts, :correlation_id),
         emitted_at: DateTime.utc_now(),
         metadata:
           %{
             payload_bytes: estimate_size(normalized_data),
             truncated: truncation_meta.truncated,
             dropped_keys: truncation_meta.dropped_keys
           }
           |> maybe_put(:source, Keyword.get(opts, :source))
       }}
    end
  end

  @spec to_message(t()) :: {:jido_document_signal, t()}
  def to_message(%__MODULE__{} = signal), do: {:jido_document_signal, signal}

  defp validate_type(type) when type in @known_types, do: :ok

  defp validate_type(type) do
    {:error,
     Error.new(:validation_failed, "unknown signal type", %{
       type: type,
       supported_types: @known_types
     })}
  end

  defp validate_session_id(session_id) when is_binary(session_id) and session_id != "", do: :ok

  defp validate_session_id(session_id) do
    {:error,
     Error.new(:validation_failed, "signal requires a non-empty session_id", %{
       session_id: session_id
     })}
  end

  defp validate_data(data) when is_map(data), do: :ok

  defp validate_data(data) do
    {:error, Error.new(:validation_failed, "signal data must be a map", %{data: data})}
  end

  defp normalize_data(data, max_payload_bytes) do
    payload_size = estimate_size(data)

    if payload_size <= max_payload_bytes do
      {data, %{truncated: false, dropped_keys: []}}
    else
      truncate_map(data, max_payload_bytes)
    end
  end

  defp truncate_map(data, max_payload_bytes) do
    sorted_keys = data |> Map.keys() |> Enum.sort_by(&to_string/1)

    {kept, dropped_keys, _size} =
      Enum.reduce(sorted_keys, {%{}, [], 0}, fn key, {acc, dropped, size} ->
        value = Map.get(data, key)
        normalized_value = truncate_value(value)
        candidate = Map.put(acc, key, normalized_value)
        candidate_size = estimate_size(candidate)

        if candidate_size <= max_payload_bytes do
          {candidate, dropped, candidate_size}
        else
          {acc, [key | dropped], size}
        end
      end)

    {Map.put(kept, :_truncated, true),
     %{truncated: true, dropped_keys: Enum.reverse(dropped_keys)}}
  end

  defp truncate_value(value) when is_binary(value) and byte_size(value) > 256 do
    binary_part(value, 0, 256) <> "..."
  end

  defp truncate_value(%{} = map) do
    map
    |> Enum.take(16)
    |> Map.new(fn {key, value} -> {key, truncate_value(value)} end)
  end

  defp truncate_value(list) when is_list(list) do
    list
    |> Enum.take(16)
    |> Enum.map(&truncate_value/1)
  end

  defp truncate_value(value), do: value

  defp estimate_size(term) do
    term |> :erlang.term_to_binary() |> byte_size()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
