defmodule Jido.Document.Action.Context do
  @moduledoc """
  Standard action context envelope.

  Input schema pattern fields:
  - `session_id`: required string identifier for scoped workflows
  - `path`: optional filesystem path
  - `document`: optional `Jido.Document.Document` snapshot
  - `options`: request-scoped options map
  """

  alias Jido.Document.Document

  @type t :: %__MODULE__{
          session_id: String.t(),
          path: Path.t() | nil,
          document: Document.t() | nil,
          actor: map() | nil,
          options: map(),
          correlation_id: String.t(),
          idempotency_key: String.t() | nil,
          metadata: map()
        }

  defstruct session_id: nil,
            path: nil,
            document: nil,
            actor: nil,
            options: %{},
            correlation_id: nil,
            idempotency_key: nil,
            metadata: %{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Jido.Document.Error.t()}
  def new(attrs) do
    attrs = to_map(attrs)

    session_id =
      attrs
      |> Map.get(:session_id)
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end

    if session_id == nil do
      {:error,
       Jido.Document.Error.new(
         :invalid_params,
         "action context requires session_id",
         %{field: :session_id, value: Map.get(attrs, :session_id)}
       )}
    else
      {:ok,
       %__MODULE__{
         session_id: session_id,
         path: normalize_optional_path(Map.get(attrs, :path)),
         document: Map.get(attrs, :document),
         actor: normalize_actor(Map.get(attrs, :actor)),
         options: normalize_options(Map.get(attrs, :options, %{})),
         correlation_id: Map.get(attrs, :correlation_id, default_correlation_id()),
         idempotency_key: Map.get(attrs, :idempotency_key),
         metadata: normalize_options(Map.get(attrs, :metadata, %{}))
       }}
    end
  end

  defp default_correlation_id do
    "jd-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp normalize_optional_path(nil), do: nil
  defp normalize_optional_path(path) when is_binary(path), do: Path.expand(path)
  defp normalize_optional_path(other), do: to_string(other)

  defp normalize_options(options) when is_map(options), do: options
  defp normalize_options(options) when is_list(options), do: Map.new(options)
  defp normalize_options(_), do: %{}

  defp normalize_actor(nil), do: nil
  defp normalize_actor(%{} = actor), do: actor
  defp normalize_actor(_), do: nil

  defp to_map(%{} = map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(_), do: %{}
end
