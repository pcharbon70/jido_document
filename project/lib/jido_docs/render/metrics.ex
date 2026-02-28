defmodule JidoDocs.Render.Metrics do
  @moduledoc """
  Lightweight counters for render strategy and queue effectiveness.
  """

  use GenServer

  @table __MODULE__

  @counters [
    :incremental_selected,
    :full_selected,
    :queue_enqueued,
    :queue_canceled,
    :queue_dropped,
    :queue_completed
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec record_strategy(:incremental | :full) :: :ok
  def record_strategy(mode) when mode in [:incremental, :full] do
    key = if mode == :incremental, do: :incremental_selected, else: :full_selected
    increment(key)
  end

  @spec increment(atom(), non_neg_integer()) :: :ok
  def increment(key, value \\ 1) when is_atom(key) and is_integer(value) and value >= 0 do
    if :ets.whereis(@table) == :undefined do
      :ok
    else
      :ets.update_counter(@table, key, value)
      :ok
    end
  rescue
    _ -> :ok
  end

  @spec snapshot() :: map()
  def snapshot do
    if :ets.whereis(@table) == :undefined do
      %{}
    else
      @counters
      |> Enum.map(fn key -> {key, counter(key)} end)
      |> Map.new()
    end
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    Enum.each(@counters, fn key ->
      :ets.insert(table, {key, 0})
    end)

    {:ok, %{table: table}}
  end

  defp counter(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      _ -> 0
    end
  end
end
