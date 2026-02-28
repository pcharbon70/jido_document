defmodule Mix.Tasks.Jido.TriageReport do
  @moduledoc """
  Generates a prioritized release-feedback triage report.

      mix jido.triage_report --input ./feedback/issues.exs
      mix jido.triage_report --input ./feedback/issues.exs --output ./feedback/triage.md --min-score 40
  """

  use Mix.Task

  alias Jido.Document.{Error, Triage}

  @shortdoc "Generate prioritized issue triage markdown"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [input: :string, output: :string, min_score: :integer]
      )

    input_path = opts[:input] || Mix.raise("missing required option --input")
    output_path = opts[:output] || "TRIAGE_REPORT.md"
    min_score = opts[:min_score]

    with {:ok, issues} <- read_issues(input_path),
         :ok <- Triage.write_markdown(issues, output_path, min_score: min_score) do
      Mix.shell().info("wrote triage report: #{output_path}")
    else
      {:error, %Error{} = error} ->
        Mix.raise("#{error.message} (code=#{error.code}, details=#{inspect(error.details)})")
    end
  end

  defp read_issues(path) do
    expanded = Path.expand(path)

    if File.regular?(expanded) do
      try do
        {issues, _binding} = Code.eval_file(expanded)

        if is_list(issues) do
          {:ok, issues}
        else
          {:error,
           Error.new(:validation_failed, "triage input must evaluate to a list", %{
             path: expanded,
             value: issues
           })}
        end
      rescue
        exception ->
          {:error,
           Error.new(:parse_failed, "failed to evaluate triage input", %{
             path: expanded,
             exception: exception.__struct__,
             message: Exception.message(exception)
           })}
      end
    else
      {:error, Error.new(:not_found, "triage input file not found", %{path: expanded})}
    end
  end
end
