defmodule Jido.Document.Audit do
  @moduledoc """
  Structured audit event schema and sink dispatch helpers.
  """

  alias Jido.Document.Error

  @schema_version 1

  @type event :: %{
          event_id: String.t(),
          schema_version: pos_integer(),
          event_type: atom(),
          action: atom(),
          status: :ok | :error | :denied,
          session_id: String.t(),
          correlation_id: String.t() | nil,
          actor: map() | nil,
          source: String.t() | nil,
          revision_id: String.t() | nil,
          document_revision: non_neg_integer() | nil,
          metadata: map(),
          emitted_at: DateTime.t()
        }

  @spec build(map()) :: {:ok, event()} | {:error, Error.t()}
  def build(attrs) when is_map(attrs) do
    with :ok <- require_action(attrs),
         :ok <- require_session_id(attrs),
         :ok <- require_status(attrs) do
      event = %{
        event_id: event_id(),
        schema_version: @schema_version,
        event_type: Map.get(attrs, :event_type, :action),
        action: Map.fetch!(attrs, :action),
        status: Map.fetch!(attrs, :status),
        session_id: Map.fetch!(attrs, :session_id),
        correlation_id: Map.get(attrs, :correlation_id),
        actor: Map.get(attrs, :actor),
        source: normalize_source(Map.get(attrs, :source)),
        revision_id: Map.get(attrs, :revision_id),
        document_revision: Map.get(attrs, :document_revision),
        metadata: Map.get(attrs, :metadata, %{}),
        emitted_at: DateTime.utc_now()
      }

      {:ok, event}
    end
  end

  @spec dispatch(event(), [module() | (event() -> term())]) :: :ok
  def dispatch(event, sinks) when is_map(event) and is_list(sinks) do
    Enum.each(sinks, fn sink ->
      _ = dispatch_to_sink(sink, event)
    end)

    :ok
  end

  defp dispatch_to_sink(sink, event) when is_function(sink, 1) do
    sink.(event)
  rescue
    _ -> :error
  end

  defp dispatch_to_sink(sink, event) when is_atom(sink) do
    if Code.ensure_loaded?(sink) and function_exported?(sink, :handle_event, 1) do
      apply(sink, :handle_event, [event])
    else
      :error
    end
  rescue
    _ -> :error
  end

  defp dispatch_to_sink(_sink, _event), do: :error

  defp require_action(attrs) do
    if is_atom(Map.get(attrs, :action)) do
      :ok
    else
      {:error, Error.new(:validation_failed, "audit event requires atom action", %{attrs: attrs})}
    end
  end

  defp require_session_id(attrs) do
    session_id = Map.get(attrs, :session_id)

    if is_binary(session_id) and session_id != "" do
      :ok
    else
      {:error, Error.new(:validation_failed, "audit event requires session_id", %{attrs: attrs})}
    end
  end

  defp require_status(attrs) do
    if Map.get(attrs, :status) in [:ok, :error, :denied] do
      :ok
    else
      {:error, Error.new(:validation_failed, "audit event status is invalid", %{attrs: attrs})}
    end
  end

  defp normalize_source(source) when is_binary(source), do: source
  defp normalize_source(source) when is_atom(source), do: Atom.to_string(source)
  defp normalize_source(_source), do: nil

  defp event_id do
    "audit-" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
