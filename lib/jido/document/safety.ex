defmodule Jido.Document.Safety do
  @moduledoc """
  Sensitive content detection and redaction helpers.
  """

  alias Jido.Document.Error

  @default_rules [
    %{code: "api_token", severity: :high, regex: ~r/\bjido_secret_[A-Za-z0-9_-]{16,}\b/},
    %{code: "aws_access_key", severity: :high, regex: ~r/\bAKIA[0-9A-Z]{16}\b/},
    %{code: "email", severity: :low, regex: ~r/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i}
  ]

  @type severity :: :low | :medium | :high

  @type finding :: %{
          code: String.t(),
          severity: severity(),
          message: String.t(),
          index: non_neg_integer(),
          length: non_neg_integer(),
          line: pos_integer(),
          column: pos_integer(),
          snippet: String.t()
        }

  @spec scan(String.t(), keyword() | map()) :: {:ok, [finding()]} | {:error, Error.t()}
  def scan(content, opts \\ %{})

  def scan(content, opts) when is_binary(content) do
    opts = to_map(opts)
    rules = normalize_rules(Map.get(opts, :rules, @default_rules))

    findings_from_rules = scan_with_rules(content, rules)

    findings_from_detectors =
      opts
      |> Map.get(:detectors, [])
      |> List.wrap()
      |> Enum.flat_map(&run_detector(&1, content))

    findings = (findings_from_rules ++ findings_from_detectors) |> Enum.sort_by(& &1.index)
    {:ok, findings}
  end

  def scan(content, _opts) do
    {:error, Error.new(:invalid_params, "scan content must be a binary", %{content: content})}
  end

  @spec redact(String.t(), [finding()], keyword() | map()) :: {:ok, String.t(), map()}
  def redact(content, findings, opts \\ %{}) when is_binary(content) and is_list(findings) do
    opts = to_map(opts)

    approved_codes =
      Map.get(opts, :approved_codes, []) |> Enum.map(&normalize_code/1) |> MapSet.new()

    {content, redacted_codes} =
      findings
      |> Enum.reject(fn finding ->
        MapSet.member?(approved_codes, normalize_code(finding.code))
      end)
      |> Enum.sort_by(& &1.index, :desc)
      |> Enum.reduce({content, []}, fn finding, {acc_content, codes} ->
        replacement = mask_for_finding(finding, opts)
        updated = replace_span(acc_content, finding.index, finding.length, replacement)
        {updated, [finding.code | codes]}
      end)

    {:ok, content,
     %{
       approved_codes: MapSet.to_list(approved_codes),
       redacted_codes: Enum.reverse(redacted_codes)
     }}
  end

  @spec enforce_save_policy([finding()], keyword() | map()) :: :ok | {:error, Error.t()}
  def enforce_save_policy(findings, opts \\ %{}) when is_list(findings) do
    opts = to_map(opts)

    block_severities =
      Map.get(opts, :block_severities, [:high]) |> Enum.map(&normalize_severity/1)

    approved_codes =
      Map.get(opts, :approved_codes, []) |> Enum.map(&normalize_code/1) |> MapSet.new()

    blocked_findings =
      Enum.filter(findings, fn finding ->
        finding.severity in block_severities and
          not MapSet.member?(approved_codes, normalize_code(finding.code))
      end)

    if blocked_findings == [] do
      :ok
    else
      {:error,
       Error.new(:validation_failed, "sensitive content policy blocked save", %{
         policy: :sensitive_content,
         findings: blocked_findings,
         remediation: [:approve_codes, :redact, :remove_sensitive_content]
       })}
    end
  end

  defp scan_with_rules(content, rules) do
    Enum.flat_map(rules, fn rule ->
      Regex.scan(rule.regex, content, return: :index, capture: :first)
      |> Enum.map(fn [{index, length}] ->
        {line, column} = line_column(content, index)
        snippet = String.slice(content, index, min(length, 32))

        %{
          code: rule.code,
          severity: rule.severity,
          message: "Sensitive content detected (#{rule.code})",
          index: index,
          length: length,
          line: line,
          column: column,
          snippet: snippet
        }
      end)
    end)
  end

  defp run_detector(detector, content) when is_function(detector, 1) do
    case detector.(content) do
      findings when is_list(findings) -> Enum.map(findings, &normalize_finding/1)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp run_detector(_detector, _content), do: []

  defp normalize_finding(%{} = finding) do
    {line, column} = line_column(finding[:content] || "", Map.get(finding, :index, 0))

    %{
      code: normalize_code(Map.get(finding, :code, "custom")),
      severity: normalize_severity(Map.get(finding, :severity, :medium)),
      message: Map.get(finding, :message, "Sensitive content detected"),
      index: Map.get(finding, :index, 0),
      length: Map.get(finding, :length, 0),
      line: Map.get(finding, :line, line),
      column: Map.get(finding, :column, column),
      snippet: Map.get(finding, :snippet, "")
    }
  end

  defp normalize_rules(rules) when is_list(rules) do
    Enum.flat_map(rules, fn
      %{code: code, severity: severity, regex: %Regex{} = regex} ->
        [%{code: normalize_code(code), severity: normalize_severity(severity), regex: regex}]

      _ ->
        []
    end)
  end

  defp normalize_rules(_), do: @default_rules

  defp normalize_code(code) when is_atom(code), do: code |> Atom.to_string() |> String.downcase()
  defp normalize_code(code) when is_binary(code), do: String.downcase(code)
  defp normalize_code(code), do: code |> to_string() |> String.downcase()

  defp normalize_severity(severity) when severity in [:low, :medium, :high], do: severity
  defp normalize_severity("low"), do: :low
  defp normalize_severity("medium"), do: :medium
  defp normalize_severity("high"), do: :high
  defp normalize_severity(_), do: :medium

  defp mask_for_finding(finding, opts) do
    mask =
      Map.get(opts, :mask, fn code, _severity ->
        "[REDACTED:#{code}]"
      end)

    case mask do
      fun when is_function(fun, 2) -> fun.(finding.code, finding.severity)
      value when is_binary(value) -> value
      _ -> "[REDACTED]"
    end
  end

  defp replace_span(content, index, length, replacement) when index >= 0 and length >= 0 do
    prefix = binary_part(content, 0, index)
    suffix = binary_part(content, index + length, byte_size(content) - index - length)
    prefix <> replacement <> suffix
  end

  defp line_column(content, index) do
    index = max(index, 0)
    head = binary_part(content, 0, min(index, byte_size(content)))
    lines = String.split(head, "\n", trim: false)
    line = length(lines)
    column = lines |> List.last() |> String.length() |> Kernel.+(1)
    {line, column}
  end

  defp to_map(%{} = map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(_), do: %{}
end
