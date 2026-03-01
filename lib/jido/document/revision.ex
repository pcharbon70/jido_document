defmodule Jido.Document.Revision do
  @moduledoc """
  Monotonic session-scoped revision metadata tracking.
  """

  @type entry :: %{
          revision_id: String.t(),
          sequence: pos_integer(),
          document_revision: non_neg_integer() | nil,
          action: atom(),
          source: String.t(),
          correlation_id: String.t() | nil,
          emitted_at: DateTime.t(),
          metadata: map()
        }

  @spec next(String.t(), non_neg_integer(), atom(), map()) :: {non_neg_integer(), entry()}
  def next(session_id, sequence, action, attrs \\ %{}) when is_binary(session_id) do
    next_sequence = sequence + 1

    entry = %{
      revision_id: "#{session_id}-#{next_sequence}",
      sequence: next_sequence,
      document_revision: Map.get(attrs, :document_revision),
      action: action,
      source: source(attrs),
      correlation_id: Map.get(attrs, :correlation_id),
      emitted_at: DateTime.utc_now(),
      metadata: Map.get(attrs, :metadata, %{})
    }

    {next_sequence, entry}
  end

  defp source(attrs) do
    case Map.get(attrs, :source) do
      source when is_binary(source) and source != "" -> source
      source when is_atom(source) -> Atom.to_string(source)
      _ -> "unknown"
    end
  end
end
