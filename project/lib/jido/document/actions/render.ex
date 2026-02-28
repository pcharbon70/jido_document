defmodule Jido.Document.Actions.Render do
  @moduledoc """
  Renders document body into preview artifacts (HTML/TOC/diagnostics).
  """

  @behaviour Jido.Document.Action

  alias Jido.Document.{Document, Error, Renderer, Safety}
  alias Jido.Document.Action.Context
  alias Jido.Document.Render.{ChangeTracker, JobQueue, Metrics}

  @impl true
  def name, do: :render

  @impl true
  def idempotency, do: :idempotent

  @impl true
  def run(params, %Context{} = context) do
    with {:ok, document} <- fetch_document(params, context),
         decision <- render_decision(params, context, document),
         :ok <- record_decision(decision),
         {:ok, payload} <- execute_render(params, context, document, decision) do
      {:ok, payload}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.from_reason({:render, reason}, %{})}
    end
  end

  defp fetch_document(params, context) do
    case Map.get(params, :document) || context.document do
      %Document{} = document -> {:ok, document}
      nil -> {:error, Error.new(:invalid_params, "missing document for render", %{})}
      other -> {:error, Error.new(:invalid_params, "invalid document payload", %{value: other})}
    end
  end

  defp execute_render(params, context, document, decision) do
    with {:ok, render_body, safety_meta} <- prepare_preview_body(document.body, params, context) do
      do_execute_render(params, context, document, decision, render_body, safety_meta)
    end
  end

  defp do_execute_render(params, context, document, decision, render_body, safety_meta) do
    if Map.get(params, :async, false) do
      queue = Map.get(params, :queue, JobQueue)
      notify_pid = Map.get(params, :notify_pid, self())
      render_opts = Map.get(params, :render_opts, [])

      with {:ok, job_id} <-
             JobQueue.enqueue(
               queue,
               context.session_id,
               document.revision,
               render_body,
               render_opts: render_opts,
               notify_pid: notify_pid,
               decision: decision
             ) do
        {:ok,
         %{
           queued: true,
           job_id: job_id,
           revision: document.revision,
           document: document,
           decision: decision
         }}
      else
        {:error, %Error{} = error} -> {:error, error}
        {:error, reason} -> {:error, Error.from_reason(reason, %{action: :render_enqueue})}
      end
    else
      with {:ok, preview} <- Renderer.render(render_body, Map.get(params, :render_opts, [])) do
        preview =
          Map.update(
            preview,
            :metadata,
            %{incremental: decision, safety: safety_meta},
            &(&1 |> Map.put(:incremental, decision) |> Map.put(:safety, safety_meta))
          )
          |> Map.update(:diagnostics, safety_diagnostics(safety_meta), fn diagnostics ->
            diagnostics ++ safety_diagnostics(safety_meta)
          end)

        {:ok,
         %{preview: preview, revision: document.revision, document: document, decision: decision}}
      end
    end
  end

  defp render_decision(params, context, document) do
    previous =
      Map.get(params, :previous_markdown) ||
        Map.get(context.options, :previous_markdown, "")

    ChangeTracker.plan(previous, document.body, Map.get(params, :incremental_opts, %{}))
  end

  defp record_decision(%{mode: mode}) when mode in [:incremental, :full] do
    Metrics.record_strategy(mode)
  end

  defp record_decision(_), do: :ok

  defp prepare_preview_body(body, params, context) do
    safety_opts = effective_safety_opts(params, context)

    if safety_opts == nil do
      {:ok, body, %{enabled: false, findings: [], redacted: false, raw_access: true}}
    else
      with {:ok, findings} <- Safety.scan(body, safety_opts),
           {:ok, redacted_body, redaction_meta} <- Safety.redact(body, findings, safety_opts) do
        {:ok, redacted_body,
         %{
           enabled: true,
           findings: findings,
           redacted: redacted_body != body,
           raw_access: true,
           approvals: redaction_meta.approved_codes
         }}
      end
    end
  end

  defp effective_safety_opts(params, context) do
    candidate =
      case Map.fetch(params, :safety) do
        {:ok, value} ->
          value

        :error ->
          Map.get(context.options, :safety, :__unset__)
      end

    if candidate == :__unset__ do
      nil
    else
      cond do
        is_map(candidate) -> candidate
        is_list(candidate) -> Map.new(candidate)
        true -> %{}
      end
    end
  end

  defp safety_diagnostics(%{enabled: true, findings: findings}) do
    Enum.map(findings, fn finding ->
      %{
        severity: finding.severity,
        message: finding.message,
        location: %{line: finding.line, column: finding.column},
        hint: "Redaction policy applied for preview output",
        code: :sensitive_content
      }
    end)
  end

  defp safety_diagnostics(_), do: []
end
