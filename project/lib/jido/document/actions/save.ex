defmodule Jido.Document.Actions.Save do
  @moduledoc """
  Serializes and persists a document to disk.
  """

  @behaviour Jido.Document.Action

  alias Jido.Document.{Document, Error, PathPolicy, Persistence, Safety}
  alias Jido.Document.Action.Context

  @impl true
  def name, do: :save

  @impl true
  def idempotency, do: :conditionally_idempotent

  @impl true
  def run(params, %Context{} = context) do
    safety_opts = effective_safety_opts(params, context)

    with {:ok, document} <- fetch_document(params, context),
         {:ok, resolved_path} <- resolve_save_path(params, context, document),
         :ok <- ensure_no_divergence(params, resolved_path),
         {:ok, serialized} <- Document.serialize(document, Map.get(params, :serialize_opts, [])),
         {:ok, findings} <- scan_sensitive_content(serialized, safety_opts),
         :ok <- enforce_sensitive_policy(findings, safety_opts),
         {:ok, disk_snapshot} <- write_file_safely(resolved_path, serialized, params),
         :ok <- persist_revision_sidecar(params, resolved_path) do
      {:ok,
       %{
         document: Document.mark_clean(document),
         path: resolved_path,
         bytes: byte_size(serialized),
         revision: document.revision,
         disk_snapshot: disk_snapshot,
         safety: %{findings: findings}
       }}
    end
  end

  defp fetch_document(params, context) do
    case Map.get(params, :document) || context.document do
      %Document{} = document -> {:ok, document}
      nil -> {:error, Error.new(:invalid_params, "missing document for save", %{})}
      other -> {:error, Error.new(:invalid_params, "invalid document payload", %{value: other})}
    end
  end

  defp resolve_save_path(params, context, %Document{} = document) do
    path = Map.get(params, :path) || context.path || document.path
    PathPolicy.resolve_path(path, context.options)
  end

  defp ensure_no_divergence(params, path) do
    baseline = Map.get(params, :baseline)
    on_conflict = Map.get(params, :on_conflict, :reject)

    baseline = normalize_baseline(path, baseline)

    case Persistence.detect_divergence(path, baseline) do
      :ok ->
        :ok

      {:error, %Error{code: :conflict} = error} when on_conflict == :overwrite ->
        _ = error
        :ok

      {:error, %Error{code: :conflict} = error} when on_conflict == :merge_hook ->
        run_merge_hook(params, path, error)

      {:error, %Error{code: :conflict} = error} ->
        {:error, enrich_conflict_error(path, error)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp run_merge_hook(params, path, %Error{} = error) do
    case Map.get(params, :merge_hook) do
      hook when is_function(hook, 3) ->
        case hook.(path, Map.get(params, :baseline), error.details) do
          :ok ->
            :ok

          {:ok, _merged_content} ->
            :ok

          {:error, reason} ->
            {:error, Error.from_reason(reason, %{path: path, conflict: error.details})}

          other ->
            {:error,
             Error.new(:conflict, "merge hook returned invalid response", %{
               path: path,
               value: other
             })}
        end

      _ ->
        {:error,
         Error.new(:conflict, "save blocked by on-disk divergence", %{
           path: path,
           conflict: error.details,
           remediation: [:reload, :overwrite, :merge_hook]
         })}
    end
  end

  defp write_file_safely(path, content, params) do
    preserve_metadata? = Map.get(params, :preserve_metadata, true)
    atomic_opts = Map.get(params, :atomic_write_opts, [])

    Persistence.atomic_write(
      path,
      content,
      Keyword.merge([preserve_metadata: preserve_metadata?], atomic_opts)
    )
  end

  defp persist_revision_sidecar(params, path) do
    case Map.get(params, :revision_metadata) do
      metadata when is_map(metadata) -> Persistence.write_revision_sidecar(path, metadata)
      _ -> :ok
    end
  end

  defp normalize_baseline(path, %{} = baseline) do
    baseline_path = Map.get(baseline, :path)

    if is_binary(baseline_path) and Path.expand(path) == Path.expand(baseline_path) do
      baseline
    else
      nil
    end
  end

  defp normalize_baseline(_path, _baseline), do: nil

  defp enrich_conflict_error(path, %Error{} = error) do
    Error.merge_details(error, %{
      path: path,
      remediation: [:reload, :overwrite, :merge_hook]
    })
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

  defp scan_sensitive_content(_content, nil), do: {:ok, []}

  defp scan_sensitive_content(content, safety_opts) do
    Safety.scan(content, safety_opts)
  end

  defp enforce_sensitive_policy(_findings, nil), do: :ok

  defp enforce_sensitive_policy(findings, safety_opts) do
    Safety.enforce_save_policy(findings, safety_opts)
  end
end
