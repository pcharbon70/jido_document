defmodule Jido.Document.Persistence do
  @moduledoc """
  Filesystem persistence helpers for durable writes and divergence checks.
  """

  alias Jido.Document.Error

  @type snapshot :: %{
          path: Path.t(),
          mtime: integer(),
          size: non_neg_integer(),
          hash: String.t(),
          captured_at_ms: integer()
        }

  @spec snapshot(Path.t()) :: {:ok, snapshot()} | {:error, Error.t()}
  def snapshot(path) when is_binary(path) do
    with {:ok, stat} <- File.stat(path, time: :posix),
         {:ok, content} <- File.read(path) do
      {:ok,
       %{
         path: Path.expand(path),
         mtime: stat.mtime,
         size: stat.size,
         hash: hash(content),
         captured_at_ms: now_ms()
       }}
    else
      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to snapshot file", %{path: path, reason: reason})}
    end
  end

  @spec detect_divergence(Path.t(), snapshot() | nil) :: :ok | {:error, Error.t()}
  def detect_divergence(_path, nil), do: :ok

  def detect_divergence(path, baseline) when is_binary(path) and is_map(baseline) do
    with {:ok, stat} <- File.stat(path, time: :posix),
         :ok <- maybe_compare_hash(path, stat, baseline) do
      :ok
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to detect divergence", %{path: path, reason: reason})}
    end
  end

  @spec atomic_write(Path.t(), iodata(), keyword()) :: {:ok, snapshot()} | {:error, Error.t()}
  def atomic_write(path, content, opts \\ []) when is_binary(path) do
    preserve_metadata? = Keyword.get(opts, :preserve_metadata, true)
    inject_failure = Keyword.get(opts, :inject_failure)

    with :ok <- ensure_dir(path),
         {:ok, original_stat} <- maybe_stat(path),
         {:ok, tmp_path} <- write_temp(path, content),
         :ok <- maybe_inject_failure(inject_failure, tmp_path),
         :ok <- maybe_preserve_metadata(tmp_path, original_stat, preserve_metadata?),
         :ok <- rename_tmp(tmp_path, path),
         :ok <- sync_dir(Path.dirname(path)),
         {:ok, snap} <- snapshot(path) do
      {:ok, snap}
    else
      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @spec write_revision_sidecar(Path.t(), map()) :: :ok | {:error, Error.t()}
  def write_revision_sidecar(path, metadata) when is_binary(path) and is_map(metadata) do
    sidecar_path = path <> ".jido.rev"
    payload = metadata |> Map.put_new(:schema_version, 1) |> :erlang.term_to_binary()

    case atomic_write(sidecar_path, payload, preserve_metadata: false) do
      {:ok, _snapshot} -> :ok
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp ensure_dir(path) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to create target directory", %{
           path: path,
           reason: reason
         })}
    end
  end

  defp maybe_stat(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} ->
        {:ok, stat}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error,
         Error.new(:filesystem_error, "failed to stat target file", %{path: path, reason: reason})}
    end
  end

  defp write_temp(path, content) do
    tmp_path = path <> ".tmp." <> Integer.to_string(System.unique_integer([:positive]))

    with {:ok, io} <- :file.open(String.to_charlist(tmp_path), [:write, :binary, :raw]),
         :ok <- :file.write(io, content),
         :ok <- :file.sync(io),
         :ok <- :file.close(io) do
      {:ok, tmp_path}
    else
      {:error, reason} ->
        _ = File.rm(tmp_path)

        {:error,
         Error.new(:filesystem_error, "failed writing temp file", %{
           path: tmp_path,
           reason: reason
         })}
    end
  end

  defp maybe_preserve_metadata(_tmp_path, nil, _preserve_metadata?), do: :ok
  defp maybe_preserve_metadata(_tmp_path, _stat, false), do: :ok

  defp maybe_preserve_metadata(tmp_path, stat, true) do
    _ = File.chmod(tmp_path, stat.mode)

    # Best-effort ownership preservation where runtime permissions allow it.
    if function_exported?(:file, :change_owner, 2) and is_integer(stat.uid) do
      _ = :file.change_owner(String.to_charlist(tmp_path), stat.uid)
    end

    if function_exported?(:file, :change_group, 2) and is_integer(stat.gid) do
      _ = :file.change_group(String.to_charlist(tmp_path), stat.gid)
    end

    :ok
  end

  defp rename_tmp(tmp_path, target_path) do
    case File.rename(tmp_path, target_path) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = File.rm(tmp_path)

        {:error,
         Error.new(:filesystem_error, "failed to atomically rename temp file", %{
           path: target_path,
           reason: reason
         })}
    end
  end

  defp sync_dir(dir_path) do
    with {:ok, io} <- :file.open(String.to_charlist(dir_path), [:read]),
         :ok <- :file.sync(io),
         :ok <- :file.close(io) do
      :ok
    else
      # Not all filesystems allow directory sync through this API.
      _ -> :ok
    end
  end

  defp maybe_inject_failure(nil, _tmp_path), do: :ok

  defp maybe_inject_failure(:after_temp_write, tmp_path) do
    _ = File.rm(tmp_path)

    {:error,
     Error.new(:filesystem_error, "simulated interruption after temp write", %{
       path: tmp_path,
       stage: :after_temp_write
     })}
  end

  defp maybe_inject_failure(_unknown, _tmp_path), do: :ok

  defp maybe_compare_hash(path, stat, baseline) do
    baseline_mtime = Map.get(baseline, :mtime)
    baseline_size = Map.get(baseline, :size)
    baseline_hash = Map.get(baseline, :hash)

    if stat.mtime == baseline_mtime and stat.size == baseline_size do
      :ok
    else
      with {:ok, content} <- File.read(path) do
        current_hash = hash(content)

        if current_hash == baseline_hash do
          :ok
        else
          {:error,
           Error.new(:conflict, "on-disk file diverged from loaded baseline", %{
             path: path,
             baseline: baseline,
             current: %{mtime: stat.mtime, size: stat.size, hash: current_hash}
           })}
        end
      else
        {:error, reason} ->
          {:error,
           Error.new(:filesystem_error, "failed to read file for divergence check", %{
             path: path,
             reason: reason
           })}
      end
    end
  end

  defp hash(content) do
    content
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp now_ms, do: System.system_time(:millisecond)
end
