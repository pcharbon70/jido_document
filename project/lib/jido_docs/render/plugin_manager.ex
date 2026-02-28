defmodule JidoDocs.Render.PluginManager do
  @moduledoc """
  Ordered plugin execution with compatibility checks and failure isolation.
  """

  @type plugin_spec :: module() | {module(), integer()}

  @spec apply_plugins(String.t(), [plugin_spec()], map()) :: {:ok, String.t(), [map()]}
  def apply_plugins(markdown, plugins, context)
      when is_binary(markdown) and is_list(plugins) and is_map(context) do
    diagnostics = []

    {final_markdown, diagnostics} =
      plugins
      |> normalize_plugins()
      |> Enum.reduce({markdown, diagnostics}, fn {plugin, _priority}, {acc_markdown, acc_diag} ->
        execute_plugin(plugin, acc_markdown, context, acc_diag)
      end)

    {:ok, final_markdown, Enum.reverse(diagnostics)}
  end

  @spec startup_check([plugin_spec()], map()) :: {:ok, [module()], [map()]}
  def startup_check(plugins, context \\ %{}) when is_list(plugins) do
    {compatible, diagnostics} =
      plugins
      |> normalize_plugins()
      |> Enum.reduce({[], []}, fn {plugin, _priority}, {acc_plugins, acc_diag} ->
        cond do
          not Code.ensure_loaded?(plugin) ->
            {acc_plugins,
             [
               diagnostic(
                 :warning,
                 "plugin module unavailable",
                 %{plugin: plugin},
                 "Ensure plugin module is compiled and loaded",
                 :plugin_unavailable
               )
               | acc_diag
             ]}

          not function_exported?(plugin, :compatible?, 1) ->
            {acc_plugins,
             [
               diagnostic(
                 :warning,
                 "plugin missing compatible?/1",
                 %{plugin: plugin},
                 "Implement JidoDocs.Render.Plugin callbacks",
                 :plugin_contract_missing
               )
               | acc_diag
             ]}

          plugin.compatible?(context) ->
            {[plugin | acc_plugins], acc_diag}

          true ->
            {acc_plugins,
             [
               diagnostic(
                 :warning,
                 "plugin marked incompatible",
                 %{plugin: plugin},
                 "Adjust plugin configuration or disable plugin",
                 :plugin_incompatible
               )
               | acc_diag
             ]}
        end
      end)

    {:ok, Enum.reverse(compatible), Enum.reverse(diagnostics)}
  end

  defp execute_plugin(plugin, markdown, context, diagnostics) do
    cond do
      not Code.ensure_loaded?(plugin) ->
        {markdown,
         [
           diagnostic(
             :warning,
             "plugin unavailable; skipped",
             %{plugin: plugin},
             "Compile and load plugin module",
             :plugin_unavailable
           )
           | diagnostics
         ]}

      not function_exported?(plugin, :transform, 2) ->
        {markdown,
         [
           diagnostic(
             :warning,
             "plugin missing transform/2; skipped",
             %{plugin: plugin},
             "Implement transform/2 callback",
             :plugin_contract_missing
           )
           | diagnostics
         ]}

      function_exported?(plugin, :compatible?, 1) and not plugin.compatible?(context) ->
        {markdown,
         [
           diagnostic(
             :warning,
             "plugin incompatible; skipped",
             %{plugin: plugin},
             "Update plugin configuration",
             :plugin_incompatible
           )
           | diagnostics
         ]}

      true ->
        try do
          case plugin.transform(markdown, context) do
            {:ok, transformed} when is_binary(transformed) ->
              {transformed, diagnostics}

            {:error, reason} ->
              {markdown,
               [
                 diagnostic(
                   :warning,
                   "plugin execution failed",
                   %{plugin: plugin, reason: inspect(reason)},
                   "Check plugin implementation and inputs",
                   :plugin_failed
                 )
                 | diagnostics
               ]}

            other ->
              {markdown,
               [
                 diagnostic(
                   :warning,
                   "plugin returned invalid payload",
                   %{plugin: plugin, payload: inspect(other)},
                   "Plugin must return {:ok, markdown} or {:error, reason}",
                   :plugin_invalid_return
                 )
                 | diagnostics
               ]}
          end
        rescue
          exception ->
            {markdown,
             [
               diagnostic(
                 :warning,
                 "plugin raised exception",
                 %{plugin: plugin, exception: inspect(exception.__struct__)},
                 "Handle errors internally in plugin transform",
                 :plugin_exception
               )
               | diagnostics
             ]}
        end
    end
  end

  defp normalize_plugins(plugins) do
    plugins
    |> Enum.map(fn
      {plugin, priority} when is_atom(plugin) and is_integer(priority) -> {plugin, priority}
      plugin when is_atom(plugin) -> {plugin, 100}
    end)
    |> Enum.sort_by(fn {plugin, priority} -> {priority, inspect(plugin)} end)
  end

  defp diagnostic(severity, message, location, hint, code) do
    %{severity: severity, message: message, location: location, hint: hint, code: code}
  end
end
