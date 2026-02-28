defmodule Jido.Document.Adapters.TUI do
  @moduledoc """
  Terminal adapter for low-latency session interaction and signal synchronization.
  """

  alias Jido.Document.Action.Result
  alias Jido.Document.{Agent, Error, SessionRegistry, Signal, SignalBus}

  @default_keymap %{
    "ctrl+l" => :load,
    "ctrl+f" => :update_frontmatter,
    "ctrl+b" => :update_body,
    "ctrl+s" => :save,
    "ctrl+z" => :undo,
    "ctrl+r" => :render
  }

  @type t :: %__MODULE__{
          registry: GenServer.server(),
          signal_bus: GenServer.server(),
          session_id: String.t(),
          session_pid: pid(),
          connected: boolean(),
          keymap: %{optional(String.t()) => atom()},
          panes: map(),
          status_bar: map(),
          viewport: map(),
          redraw: map()
        }

  defstruct registry: SessionRegistry,
            signal_bus: SignalBus,
            session_id: nil,
            session_pid: nil,
            connected: false,
            keymap: @default_keymap,
            panes: %{
              layout: :split,
              editor: %{body: "", cursor_line: 1, cursor_column: 1},
              preview: %{html: "", toc: [], diagnostics: []}
            },
            status_bar: %{
              revision: nil,
              save_state: :idle,
              message: "disconnected",
              error: nil,
              lock_owner: nil,
              connected: false
            },
            viewport: %{
              width: 120,
              height: 40,
              color_mode: :full
            },
            redraw: %{
              last_ms: nil,
              min_interval_ms: 60,
              pending: false
            }

  @spec connect(map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def connect(params, opts \\ []) when is_map(params) do
    registry = Keyword.get(opts, :registry, SessionRegistry)
    signal_bus = Keyword.get(opts, :signal_bus, SignalBus)
    keymap = Keyword.get(opts, :keymap, @default_keymap)

    with {:ok, session_info} <- ensure_session(registry, params),
         :ok <- SignalBus.subscribe(signal_bus, session_info.session_id, pid: self()) do
      adapter = %__MODULE__{
        registry: registry,
        signal_bus: signal_bus,
        session_id: session_info.session_id,
        session_pid: session_info.pid,
        connected: true,
        keymap: keymap
      }

      {:ok, refresh_snapshot(adapter, message: "connected")}
    end
  end

  @spec disconnect(t(), term()) :: t()
  def disconnect(%__MODULE__{} = adapter, reason \\ :transport_lost) do
    adapter
    |> put_connected(false)
    |> put_status(error: nil, message: "disconnected: #{inspect(reason)}")
  end

  @spec reconnect(t()) :: {:ok, t()} | {:error, Error.t()}
  def reconnect(%__MODULE__{} = adapter) do
    with {:ok, session_info} <-
           SessionRegistry.ensure_session(adapter.registry, adapter.session_id),
         :ok <- SignalBus.subscribe(adapter.signal_bus, session_info.session_id, pid: self()) do
      updated = %{adapter | session_pid: session_info.pid}
      {:ok, refresh_snapshot(put_connected(updated, true), message: "reconnected")}
    end
  end

  @spec keymap() :: map()
  def keymap, do: @default_keymap

  @spec handle_key(t(), String.t(), map()) :: {:ok, t()} | {:error, Error.t(), t()}
  def handle_key(%__MODULE__{} = adapter, key, payload \\ %{})
      when is_binary(key) and is_map(payload) do
    if adapter.connected do
      case Map.get(adapter.keymap, key) do
        nil ->
          {:error, Error.new(:invalid_params, "unknown keybinding", %{key: key}), adapter}

        :undo ->
          error =
            Error.new(:internal, "undo not yet available in current agent contract", %{key: key})

          {:error, error, put_status(adapter, error: error.message)}

        action ->
          run_action(adapter, action, payload)
      end
    else
      error = Error.new(:subscription_error, "adapter disconnected", %{key: key})
      {:error, error, put_status(adapter, error: error.message)}
    end
  end

  @spec set_viewport(t(), map()) :: t()
  def set_viewport(%__MODULE__{} = adapter, %{width: width, height: height} = attrs)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    colors = Map.get(attrs, :colors, 256)

    color_mode =
      cond do
        Map.get(attrs, :low_color, false) -> :low
        colors <= 16 -> :low
        true -> :full
      end

    layout = layout_for_width(width)

    adapter
    |> Map.update!(
      :viewport,
      &Map.merge(&1, %{width: width, height: height, color_mode: color_mode})
    )
    |> Map.update!(:panes, &Map.put(&1, :layout, layout))
  end

  @spec render_frame(t(), keyword()) :: {:ok, map(), t()} | {:deferred, t()}
  def render_frame(%__MODULE__{} = adapter, opts \\ []) do
    now_ms = Keyword.get(opts, :now_ms, System.monotonic_time(:millisecond))
    force? = Keyword.get(opts, :force, false)

    case can_redraw?(adapter.redraw, now_ms, force?) do
      true ->
        frame = build_frame(adapter)

        updated =
          %{adapter | redraw: %{adapter.redraw | last_ms: now_ms, pending: false}}

        {:ok, frame, updated}

      false ->
        {:deferred, %{adapter | redraw: %{adapter.redraw | pending: true}}}
    end
  end

  @spec handle_signal(t(), Signal.t()) :: t()
  def handle_signal(%__MODULE__{} = adapter, %Signal{session_id: session_id} = signal)
      when session_id == adapter.session_id do
    adapter =
      adapter
      |> refresh_snapshot()
      |> apply_status_from_signal(signal)

    if get_in(signal.data, [:action]) == :lock_state do
      put_status(adapter, lock_owner: get_in(signal.data, [:payload, :owner]))
    else
      adapter
    end
  end

  def handle_signal(adapter, _signal), do: adapter

  defp ensure_session(registry, params) do
    cond do
      is_binary(params[:session_id]) ->
        SessionRegistry.ensure_session(registry, params[:session_id])

      is_binary(params["session_id"]) ->
        SessionRegistry.ensure_session(registry, params["session_id"])

      is_binary(params[:path]) ->
        SessionRegistry.ensure_session_by_path(registry, params[:path])

      is_binary(params["path"]) ->
        SessionRegistry.ensure_session_by_path(registry, params["path"])

      true ->
        {:error,
         Error.new(:invalid_params, "connect requires session_id or path", %{params: params})}
    end
  end

  defp run_action(adapter, action, payload) do
    SessionRegistry.touch(adapter.registry, adapter.session_id)

    params =
      case action do
        :load ->
          normalize_load_params(payload)

        :save ->
          normalize_save_params(payload)

        :update_frontmatter ->
          %{changes: Map.get(payload, :changes, Map.get(payload, "changes", %{}))}

        :update_body ->
          %{body: Map.get(payload, :body, Map.get(payload, "body", ""))}

        :render ->
          %{}
      end

    case Agent.command(adapter.session_pid, action, params) do
      %Result{status: :ok} ->
        {:ok,
         refresh_snapshot(adapter)
         |> put_status(error: nil, save_state: status_for_action(action))}

      %Result{status: :error, error: %Error{} = error} ->
        {:error, error,
         refresh_snapshot(adapter) |> put_status(error: error.message, save_state: :error)}
    end
  end

  defp refresh_snapshot(adapter, overrides \\ []) do
    state = Agent.state(adapter.session_pid)
    document = state.document
    preview = state.preview || %{}
    layout = layout_for_width(adapter.viewport.width)

    panes = %{
      layout: layout,
      editor: %{
        body: (document && document.body) || "",
        cursor_line: 1,
        cursor_column: 1
      },
      preview: %{
        html: Map.get(preview, :html, ""),
        toc: Map.get(preview, :toc, []),
        diagnostics: Map.get(preview, :diagnostics, [])
      }
    }

    status_updates = %{
      revision: document && document.revision,
      connected: adapter.connected,
      message: Keyword.get(overrides, :message, adapter.status_bar.message)
    }

    adapter
    |> Map.put(:panes, panes)
    |> put_status(status_updates)
  end

  defp apply_status_from_signal(adapter, %Signal{type: :saved}) do
    put_status(adapter, save_state: :saved, error: nil)
  end

  defp apply_status_from_signal(adapter, %Signal{type: :failed, data: data}) do
    message =
      data
      |> Map.get(:error, %{})
      |> Map.get(:message, "action failed")

    put_status(adapter, save_state: :error, error: message)
  end

  defp apply_status_from_signal(adapter, _signal), do: adapter

  defp put_connected(adapter, connected) do
    %{adapter | connected: connected}
    |> put_status(connected: connected)
  end

  defp put_status(%__MODULE__{} = adapter, attrs) when is_list(attrs) do
    put_status(adapter, Map.new(attrs))
  end

  defp put_status(%__MODULE__{} = adapter, attrs) when is_map(attrs) do
    %{adapter | status_bar: Map.merge(adapter.status_bar, attrs)}
  end

  defp normalize_load_params(payload) do
    cond do
      is_binary(payload[:path]) -> %{path: payload[:path]}
      is_binary(payload["path"]) -> %{path: payload["path"]}
      true -> payload
    end
  end

  defp normalize_save_params(payload) do
    cond do
      is_binary(payload[:path]) -> %{path: payload[:path]}
      is_binary(payload["path"]) -> %{path: payload["path"]}
      true -> payload
    end
  end

  defp status_for_action(:save), do: :saving
  defp status_for_action(_), do: :idle

  defp layout_for_width(width) when width < 100, do: :stacked
  defp layout_for_width(_width), do: :split

  defp can_redraw?(%{last_ms: nil}, _now_ms, _force?), do: true
  defp can_redraw?(_redraw, _now_ms, true), do: true

  defp can_redraw?(%{last_ms: last_ms, min_interval_ms: min_interval}, now_ms, false) do
    now_ms - last_ms >= min_interval
  end

  defp build_frame(adapter) do
    preview_lines =
      adapter.panes.preview.html
      |> String.split("\n")
      |> Enum.take(max(adapter.viewport.height - 4, 1))

    %{
      layout: adapter.panes.layout,
      editor: adapter.panes.editor,
      preview: Map.put(adapter.panes.preview, :html_excerpt, Enum.join(preview_lines, "\n")),
      status_bar: adapter.status_bar,
      viewport: adapter.viewport
    }
  end
end
