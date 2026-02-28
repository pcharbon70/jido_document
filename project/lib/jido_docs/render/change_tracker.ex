defmodule JidoDocs.Render.ChangeTracker do
  @moduledoc """
  Change analysis and incremental-render decision helper.

  The module estimates changed regions and decides whether to keep an
  incremental strategy or fall back to full rerender.
  """

  @type region :: %{
          start_line: pos_integer(),
          end_line: pos_integer(),
          type: :replace | :insert | :delete
        }

  @type decision :: %{
          mode: :incremental | :full,
          changed_regions: [region()],
          changed_lines: non_neg_integer(),
          total_lines: non_neg_integer(),
          changed_ratio: float(),
          reason: atom()
        }

  @default_threshold_ratio 0.30
  @default_threshold_lines 120

  @spec plan(String.t(), String.t(), keyword() | map()) :: decision()
  def plan(previous_markdown, current_markdown, opts \\ %{})
      when is_binary(previous_markdown) and is_binary(current_markdown) do
    opts = normalize_opts(opts)

    previous_lines = String.split(previous_markdown, "\n", trim: false)
    current_lines = String.split(current_markdown, "\n", trim: false)

    {regions, changed_lines} = changed_regions(previous_lines, current_lines)

    total_lines = max(length(previous_lines), length(current_lines))
    changed_ratio = ratio(changed_lines, total_lines)

    {mode, reason} =
      cond do
        total_lines == 0 -> {:incremental, :empty_document}
        changed_lines == 0 -> {:incremental, :no_change}
        changed_ratio > opts.threshold_ratio -> {:full, :ratio_threshold_exceeded}
        changed_lines > opts.threshold_lines -> {:full, :line_threshold_exceeded}
        true -> {:incremental, :within_incremental_threshold}
      end

    %{
      mode: mode,
      changed_regions: regions,
      changed_lines: changed_lines,
      total_lines: total_lines,
      changed_ratio: changed_ratio,
      reason: reason
    }
  end

  defp changed_regions(previous_lines, current_lines) do
    max_len = max(length(previous_lines), length(current_lines))

    {regions, active_region, changed} =
      Enum.reduce(1..max_len, {[], nil, 0}, fn line_no, {regions, active, changed} ->
        previous = Enum.at(previous_lines, line_no - 1)
        current = Enum.at(current_lines, line_no - 1)

        case {previous, current} do
          {a, a} ->
            case active do
              nil -> {regions, nil, changed}
              region -> {[close_region(region, line_no - 1) | regions], nil, changed}
            end

          {nil, _} ->
            region = active || %{start_line: line_no, end_line: line_no, type: :insert}
            {regions, Map.put(region, :end_line, line_no), changed + 1}

          {_, nil} ->
            region = active || %{start_line: line_no, end_line: line_no, type: :delete}
            {regions, Map.put(region, :end_line, line_no), changed + 1}

          {_old, _new} ->
            region = active || %{start_line: line_no, end_line: line_no, type: :replace}
            {regions, Map.put(region, :end_line, line_no), changed + 1}
        end
      end)

    regions =
      case active_region do
        nil -> regions
        region -> [region | regions]
      end

    {Enum.reverse(regions), changed}
  end

  defp close_region(region, end_line), do: %{region | end_line: max(region.start_line, end_line)}

  defp ratio(_changed, 0), do: 0.0
  defp ratio(changed, total), do: changed / total

  defp normalize_opts(%{} = opts) do
    %{
      threshold_ratio: Map.get(opts, :threshold_ratio, @default_threshold_ratio),
      threshold_lines: Map.get(opts, :threshold_lines, @default_threshold_lines)
    }
  end

  defp normalize_opts(opts) when is_list(opts), do: normalize_opts(Map.new(opts))
  defp normalize_opts(_), do: normalize_opts(%{})
end
