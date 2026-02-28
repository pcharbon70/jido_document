defmodule Jido.Document.History do
  @moduledoc """
  Bounded snapshot history model for reversible document operations.
  """

  alias Jido.Document.Document

  @type entry :: %{
          document: Document.t(),
          action: atom(),
          timestamp: DateTime.t(),
          source: map()
        }

  @type t :: %__MODULE__{
          undo: [entry()],
          redo: [entry()],
          limit: pos_integer()
        }

  defstruct undo: [],
            redo: [],
            limit: 100

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{limit: max(Keyword.get(opts, :limit, 100), 1)}
  end

  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = history) do
    %__MODULE__{limit: history.limit}
  end

  @spec record(t(), Document.t() | nil, atom(), map()) :: t()
  def record(history, document, action, source \\ %{})

  @spec record(t(), Document.t() | nil, atom(), map()) :: t()
  def record(history, nil, _action, _source), do: history

  def record(%__MODULE__{} = history, %Document{} = document, action, source) do
    entry = %{
      document: document,
      action: action,
      timestamp: DateTime.utc_now(),
      source: normalize_source(source)
    }

    undo = [entry | history.undo] |> Enum.take(history.limit)
    %{history | undo: undo, redo: []}
  end

  @spec undo(t(), Document.t() | nil) :: {:ok, Document.t(), t()} | {:error, :empty}
  def undo(%__MODULE__{undo: []}, _current_document), do: {:error, :empty}

  def undo(%__MODULE__{undo: [entry | rest]} = history, current_document) do
    redo = maybe_push(history.redo, current_document, :undo, %{})
    {:ok, entry.document, %{history | undo: rest, redo: redo |> Enum.take(history.limit)}}
  end

  @spec redo(t(), Document.t() | nil) :: {:ok, Document.t(), t()} | {:error, :empty}
  def redo(%__MODULE__{redo: []}, _current_document), do: {:error, :empty}

  def redo(%__MODULE__{redo: [entry | rest]} = history, current_document) do
    undo = maybe_push(history.undo, current_document, :redo, %{})
    {:ok, entry.document, %{history | redo: rest, undo: undo |> Enum.take(history.limit)}}
  end

  @spec state(t()) :: map()
  def state(%__MODULE__{} = history) do
    %{
      can_undo: history.undo != [],
      can_redo: history.redo != [],
      undo_depth: length(history.undo),
      redo_depth: length(history.redo),
      limit: history.limit
    }
  end

  defp maybe_push(entries, nil, _action, _source), do: entries

  defp maybe_push(entries, %Document{} = document, action, source) do
    [
      %{
        document: document,
        action: action,
        timestamp: DateTime.utc_now(),
        source: normalize_source(source)
      }
      | entries
    ]
  end

  defp normalize_source(%{} = source), do: source
  defp normalize_source(_), do: %{}
end
