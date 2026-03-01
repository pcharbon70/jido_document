defmodule Jido.Document.Triage do
  @moduledoc """
  Helpers for release feedback intake and prioritized triage output.
  """

  alias Jido.Document.Error

  @severity_weights %{
    critical: 100,
    high: 60,
    medium: 30,
    low: 10
  }

  @type severity :: :critical | :high | :medium | :low

  @type issue :: %{
          optional(:id) => String.t(),
          optional(:summary) => String.t(),
          optional(:component) => String.t(),
          optional(:source) => String.t(),
          optional(:severity) => severity() | String.t(),
          optional(:frequency) => non_neg_integer(),
          optional(:reproducible) => boolean()
        }

  @spec prioritize([issue()], keyword()) :: [map()]
  def prioritize(issues, opts \\ []) when is_list(issues) and is_list(opts) do
    min_score = Keyword.get(opts, :min_score)

    issues
    |> Enum.map(&normalize_issue/1)
    |> Enum.map(&with_score/1)
    |> maybe_filter_min_score(min_score)
    |> Enum.sort_by(fn issue ->
      {
        -issue.priority_score,
        severity_sort(issue.severity),
        issue.id
      }
    end)
  end

  @spec to_markdown([issue()], keyword()) :: String.t()
  def to_markdown(issues, opts \\ []) do
    prioritized = prioritize(issues, opts)
    date = Date.utc_today() |> Date.to_iso8601()
    severity_counts = count_by_severity(prioritized)

    lines =
      Enum.map(prioritized, fn issue ->
        "- [#{issue.priority_score}] #{issue.severity} #{issue.id} (#{issue.component}) - #{issue.summary}"
      end)

    """
    # Release Feedback Triage

    Generated: #{date}

    ## Prioritized Issues
    #{Enum.join(lines, "\n")}

    ## Severity Totals
    - critical: #{Map.get(severity_counts, :critical, 0)}
    - high: #{Map.get(severity_counts, :high, 0)}
    - medium: #{Map.get(severity_counts, :medium, 0)}
    - low: #{Map.get(severity_counts, :low, 0)}
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @spec write_markdown([issue()], Path.t(), keyword()) :: :ok | {:error, Error.t()}
  def write_markdown(issues, path, opts \\ [])

  def write_markdown(issues, path, opts) when is_list(issues) and is_binary(path) do
    markdown = to_markdown(issues, opts)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, markdown) do
      :ok
    else
      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to write triage report", %{
           path: path,
           reason: reason
         })}
    end
  end

  def write_markdown(_issues, path, _opts) do
    {:error, Error.new(:invalid_params, "path must be a string", %{path: path})}
  end

  defp normalize_issue(issue) when is_map(issue) do
    %{
      id: get(issue, :id, "issue-" <> Integer.to_string(System.unique_integer([:positive]))),
      summary: get(issue, :summary, "no summary provided"),
      component: get(issue, :component, "unknown"),
      source: get(issue, :source, "release-feedback"),
      severity: normalize_severity(get(issue, :severity, :low)),
      frequency: max(get(issue, :frequency, 1), 1),
      reproducible: get(issue, :reproducible, false) == true
    }
  end

  defp normalize_issue(other) do
    normalize_issue(%{id: "invalid-input", summary: inspect(other), severity: :low})
  end

  defp with_score(issue) do
    severity_score = Map.fetch!(@severity_weights, issue.severity)
    frequency_score = min(issue.frequency, 50) * 2
    reproducible_score = if issue.reproducible, do: 5, else: 0

    Map.put(issue, :priority_score, severity_score + frequency_score + reproducible_score)
  end

  defp maybe_filter_min_score(issues, nil), do: issues

  defp maybe_filter_min_score(issues, min_score) when is_integer(min_score) do
    Enum.filter(issues, fn issue -> issue.priority_score >= min_score end)
  end

  defp maybe_filter_min_score(issues, _other), do: issues

  defp count_by_severity(prioritized) do
    Enum.reduce(prioritized, %{}, fn issue, acc ->
      Map.update(acc, issue.severity, 1, &(&1 + 1))
    end)
  end

  defp severity_sort(:critical), do: 0
  defp severity_sort(:high), do: 1
  defp severity_sort(:medium), do: 2
  defp severity_sort(:low), do: 3

  defp normalize_severity(value) when value in [:critical, :high, :medium, :low], do: value

  defp normalize_severity(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "critical" -> :critical
      "high" -> :high
      "medium" -> :medium
      "low" -> :low
      _ -> :low
    end
  end

  defp normalize_severity(_value), do: :low

  defp get(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
