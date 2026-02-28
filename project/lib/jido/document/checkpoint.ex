defmodule Jido.Document.Checkpoint do
  @moduledoc """
  Session checkpoint persistence for autosave and crash recovery flows.
  """

  alias Jido.Document.{Document, Error}

  @type payload :: %{
          schema_version: pos_integer(),
          session_id: String.t(),
          document: Document.t(),
          disk_snapshot: map() | nil,
          captured_at_ms: integer()
        }

  @spec checkpoint_dir(keyword()) :: Path.t()
  def checkpoint_dir(opts \\ []) do
    opts
    |> Keyword.get(:dir, default_dir())
    |> Path.expand()
  end

  @spec checkpoint_path(String.t(), keyword()) :: Path.t()
  def checkpoint_path(session_id, opts \\ []) when is_binary(session_id) do
    Path.join(checkpoint_dir(opts), session_id <> ".checkpoint")
  end

  @spec write(String.t(), Document.t(), map() | nil, keyword()) :: {:ok, Path.t()} | {:error, Error.t()}
  def write(session_id, %Document{} = document, disk_snapshot, opts \\ []) do
    path = checkpoint_path(session_id, opts)

    payload = %{
      schema_version: 1,
      session_id: session_id,
      document: document,
      disk_snapshot: disk_snapshot,
      captured_at_ms: now_ms()
    }

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, :erlang.term_to_binary(payload), [:binary]) do
      {:ok, path}
    else
      {:error, reason} ->
        {:error, Error.new(:filesystem_error, "failed to write checkpoint", %{path: path, reason: reason})}
    end
  end

  @spec load(String.t(), keyword()) :: {:ok, payload()} | {:error, :not_found | Error.t()}
  def load(session_id, opts \\ []) when is_binary(session_id) do
    path = checkpoint_path(session_id, opts)

    case File.read(path) do
      {:ok, binary} ->
        decode_payload(binary, path)

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, Error.new(:filesystem_error, "failed to read checkpoint", %{path: path, reason: reason})}
    end
  end

  @spec discard(String.t(), keyword()) :: :ok | {:error, Error.t()}
  def discard(session_id, opts \\ []) when is_binary(session_id) do
    path = checkpoint_path(session_id, opts)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, Error.new(:filesystem_error, "failed to remove checkpoint", %{path: path, reason: reason})}
    end
  end

  @spec list_orphans(keyword()) :: {:ok, [Path.t()]} | {:error, Error.t()}
  def list_orphans(opts \\ []) do
    dir = checkpoint_dir(opts)

    case File.ls(dir) do
      {:ok, entries} ->
        files =
          entries
          |> Enum.filter(&String.ends_with?(&1, ".checkpoint"))
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.sort()

        {:ok, files}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, Error.new(:filesystem_error, "failed to list checkpoint directory", %{path: dir, reason: reason})}
    end
  end

  defp decode_payload(binary, path) do
    payload = :erlang.binary_to_term(binary, [:safe])

    cond do
      not is_map(payload) ->
        {:error, Error.new(:parse_failed, "invalid checkpoint payload", %{path: path})}

      payload[:schema_version] != 1 ->
        {:error, Error.new(:validation_failed, "unsupported checkpoint schema version", %{path: path, schema_version: payload[:schema_version]})}

      not match?(%Document{}, payload[:document]) ->
        {:error, Error.new(:validation_failed, "checkpoint missing document payload", %{path: path})}

      true ->
        {:ok, payload}
    end
  rescue
    exception ->
      {:error, Error.from_exception(exception, %{path: path, stage: :decode_checkpoint})}
  end

  defp default_dir do
    Path.join(System.tmp_dir!(), "jido_document_checkpoints")
  end

  defp now_ms, do: System.system_time(:millisecond)
end
