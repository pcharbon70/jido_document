defmodule JidoDocs.Actions.Render do
  @moduledoc """
  Renders document body into preview artifacts (HTML/TOC/diagnostics).
  """

  @behaviour JidoDocs.Action

  alias JidoDocs.{Document, Error, Renderer}
  alias JidoDocs.Action.Context
  alias JidoDocs.Render.{ChangeTracker, JobQueue, Metrics}

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
    if Map.get(params, :async, false) do
      queue = Map.get(params, :queue, JobQueue)
      notify_pid = Map.get(params, :notify_pid, self())
      render_opts = Map.get(params, :render_opts, [])

      with {:ok, job_id} <-
             JobQueue.enqueue(
               queue,
               context.session_id,
               document.revision,
               document.body,
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
      with {:ok, preview} <- Renderer.render(document.body, Map.get(params, :render_opts, [])) do
        preview =
          Map.update(
            preview,
            :metadata,
            %{incremental: decision},
            &Map.put(&1, :incremental, decision)
          )

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
end
