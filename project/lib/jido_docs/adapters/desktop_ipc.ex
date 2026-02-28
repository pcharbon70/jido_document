defmodule JidoDocs.Adapters.DesktopIPC do
  @moduledoc """
  Desktop IPC message contracts for command requests and signal events.
  """

  alias JidoDocs.{Error, Signal}

  @supported_actions [:load, :save, :update_frontmatter, :update_body, :render, :force_takeover]

  @type request :: %{
          request_id: String.t(),
          action: atom(),
          session_id: String.t() | nil,
          path: String.t() | nil,
          params: map(),
          lock_token: String.t() | nil,
          replay_from_revision: integer() | nil
        }

  @spec supported_actions() :: [atom()]
  def supported_actions, do: @supported_actions

  @spec decode_request(map()) :: {:ok, request()} | {:error, Error.t()}
  def decode_request(payload) when is_map(payload) do
    with :ok <- validate_type(payload),
         {:ok, action} <- parse_action(payload),
         :ok <- validate_session_selector(payload),
         {:ok, params} <- fetch_params(payload) do
      {:ok,
       %{
         request_id: fetch_request_id(payload),
         action: action,
         session_id: fetch(payload, :session_id),
         path: fetch(payload, :path),
         params: params,
         lock_token: fetch(payload, :lock_token),
         replay_from_revision: fetch(payload, :replay_from_revision)
       }}
    end
  end

  def decode_request(payload) do
    {:error, Error.new(:invalid_params, "IPC payload must be a map", %{payload: payload})}
  end

  @spec encode_ok_response(request(), map()) :: map()
  def encode_ok_response(request, payload) do
    %{
      "type" => "action.response",
      "request_id" => request.request_id,
      "status" => "ok",
      "action" => Atom.to_string(request.action),
      "session_id" => request.session_id,
      "payload" => payload
    }
  end

  @spec encode_error_response(request() | nil, Error.t()) :: map()
  def encode_error_response(request, %Error{} = error) do
    %{
      "type" => "action.response",
      "request_id" => request && request.request_id,
      "status" => "error",
      "action" => request && Atom.to_string(request.action),
      "session_id" => request && request.session_id,
      "error" => Error.to_map(error)
    }
  end

  @spec encode_signal_event(Signal.t(), keyword()) :: map()
  def encode_signal_event(%Signal{} = signal, opts \\ []) do
    %{
      "type" => "session.signal",
      "channel" => "session:" <> signal.session_id,
      "session_id" => signal.session_id,
      "event" => Atom.to_string(signal.type),
      "schema_version" => signal.schema_version,
      "revision" => revision_from(signal),
      "data" => stringify_map(signal.data),
      "emitted_at" => DateTime.to_iso8601(signal.emitted_at),
      "metadata" => stringify_map(signal.metadata)
    }
    |> maybe_put("source", Keyword.get(opts, :source))
  end

  @spec conflict_prompt_event(String.t(), String.t(), map()) :: map()
  def conflict_prompt_event(window_id, session_id, details) do
    %{
      "type" => "editor.conflict_prompt",
      "window_id" => to_string(window_id),
      "session_id" => session_id,
      "message" => "Simultaneous edit detected. Choose takeover or refresh.",
      "details" => stringify_map(details)
    }
  end

  defp fetch(payload, key), do: Map.get(payload, key) || Map.get(payload, Atom.to_string(key))

  defp validate_type(payload) do
    case fetch(payload, :type) do
      "action.request" ->
        :ok

      other ->
        {:error,
         Error.new(:invalid_params, "IPC request type must be action.request", %{type: other})}
    end
  end

  defp parse_action(payload) do
    case fetch(payload, :action) do
      action when is_atom(action) and action in @supported_actions ->
        {:ok, action}

      action when is_binary(action) ->
        parsed =
          try do
            String.to_existing_atom(action)
          rescue
            ArgumentError -> :unsupported
          end

        if parsed in @supported_actions do
          {:ok, parsed}
        else
          {:error, Error.new(:invalid_params, "unsupported action", %{action: action})}
        end

      other ->
        {:error, Error.new(:invalid_params, "missing or invalid action", %{action: other})}
    end
  end

  defp validate_session_selector(payload) do
    session_id = fetch(payload, :session_id)
    path = fetch(payload, :path)

    if is_binary(session_id) or is_binary(path) do
      :ok
    else
      {:error,
       Error.new(:invalid_params, "request requires session_id or path", %{payload: payload})}
    end
  end

  defp fetch_params(payload) do
    case fetch(payload, :params) do
      nil -> {:ok, %{}}
      params when is_map(params) -> {:ok, params}
      other -> {:error, Error.new(:invalid_params, "params must be a map", %{params: other})}
    end
  end

  defp fetch_request_id(payload) do
    case fetch(payload, :request_id) do
      id when is_binary(id) and id != "" ->
        id

      _ ->
        "req-" <> Integer.to_string(System.unique_integer([:positive]))
    end
  end

  defp revision_from(%Signal{data: data}) do
    data[:revision] || get_in(data, [:payload, :document_revision])
  end

  defp stringify_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stringify_value(value)} end)
    |> Map.new()
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(list) when is_list(list), do: Enum.map(list, &stringify_value/1)
  defp stringify_value(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
