defmodule JidoDocs.Renderer do
  @moduledoc """
  Markdown rendering pipeline for preview generation.

  Defaults:
  - Adapter: `:mdex` (with deterministic fallback to `:simple`)
  - Frontmatter is stripped from preview output
  - Syntax highlighting path is enabled for fenced code blocks
  """

  alias JidoDocs.{Error, Frontmatter}

  @default_extensions %{
    autolink: true,
    tables: true,
    strikethrough: true,
    tasklist: true,
    smart_punctuation: true
  }

  @default_syntax_highlight %{
    enabled: true,
    theme: "onedark",
    supported_languages: ~w(elixir erl js ts json bash sh yaml toml markdown md html css sql text)
  }

  @default_opts %{
    adapter: :mdex,
    strip_frontmatter: true,
    extensions: @default_extensions,
    syntax_highlight: @default_syntax_highlight,
    frontmatter_syntax: nil
  }

  @type severity :: :info | :warning | :error

  @type diagnostic :: %{
          severity: severity(),
          message: String.t(),
          location: map() | nil,
          hint: String.t() | nil,
          code: atom() | nil
        }

  @type heading :: %{
          level: pos_integer(),
          id: String.t(),
          href: String.t(),
          title: String.t(),
          line: pos_integer()
        }

  @type output :: %{
          html: String.t(),
          toc: [heading()],
          diagnostics: [diagnostic()],
          cache_key: String.t(),
          adapter: atom(),
          metadata: map()
        }

  @spec render(String.t(), keyword() | map()) :: {:ok, output()} | {:error, Error.t()}
  def render(markdown, opts \\ %{}) when is_binary(markdown) do
    config = normalize_opts(opts)

    with {:ok, prepared, prep_diagnostics} <- prepare_markdown(markdown, config),
         {:ok, html, adapter, render_diagnostics} <- render_html(prepared, config) do
      toc = extract_headings(prepared)
      diagnostics = prep_diagnostics ++ render_diagnostics

      {:ok,
       %{
         html: html,
         toc: toc,
         diagnostics: diagnostics,
         cache_key: cache_key(prepared, config, adapter),
         adapter: adapter,
         metadata: %{
           source_bytes: byte_size(prepared),
           heading_count: length(toc),
           extensions: config.extensions,
           syntax_highlight: config.syntax_highlight
         }
       }}
    end
  rescue
    exception ->
      {:error,
       Error.from_exception(exception, %{component: :renderer, operation: :render_pipeline})}
  end

  @spec cache_key(String.t(), map(), atom()) :: String.t()
  def cache_key(markdown, config, adapter) do
    input = %{
      markdown: markdown,
      adapter: adapter,
      extensions: config.extensions,
      syntax_highlight: config.syntax_highlight,
      strip_frontmatter: config.strip_frontmatter
    }

    input
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec fallback_preview(String.t(), Error.t() | term(), keyword() | map()) :: output()
  def fallback_preview(markdown, error_or_reason, opts \\ %{}) when is_binary(markdown) do
    config = normalize_opts(opts)

    reason =
      if match?(%Error{}, error_or_reason),
        do: error_or_reason,
        else: Error.from_reason(error_or_reason, %{component: :renderer})

    normalized =
      markdown
      |> String.replace("\r\n", "\n")
      |> maybe_strip_frontmatter(config.strip_frontmatter)

    %{
      html: "<pre>#{escape_html(normalized)}</pre>",
      toc: [],
      diagnostics: [
        diagnostic(
          :error,
          "fallback preview active: #{reason.message}",
          nil,
          "Fix render issues and re-run render to recover normal preview mode",
          :fallback_preview
        )
      ],
      cache_key: cache_key(normalized, config, :fallback),
      adapter: :fallback,
      metadata: %{fallback: true, source_bytes: byte_size(normalized)}
    }
  end

  defp normalize_opts(opts) when is_list(opts), do: normalize_opts(Map.new(opts))

  defp normalize_opts(%{} = opts) do
    merged = deep_merge(@default_opts, opts)

    syntax_highlight =
      merged
      |> Map.get(:syntax_highlight, %{})
      |> deep_merge(@default_syntax_highlight)

    %{merged | syntax_highlight: syntax_highlight}
  end

  defp prepare_markdown(raw, %{strip_frontmatter: true}) do
    case Frontmatter.split(raw) do
      {:ok, %{body: body}} ->
        {:ok, body, []}

      {:error, error} ->
        # If frontmatter is malformed, keep full content in preview but emit diagnostics.
        diagnosis =
          diagnostic(
            :warning,
            "frontmatter parse warning; rendering full source",
            %{
              line: get_in(error, [:value, :line]) || 1
            },
            "Check frontmatter delimiters and syntax",
            :frontmatter_warning
          )

        {:ok, raw, [diagnosis]}
    end
  end

  defp prepare_markdown(raw, _config), do: {:ok, raw, []}

  defp maybe_strip_frontmatter(raw, true) do
    case Frontmatter.split(raw) do
      {:ok, %{body: body}} -> body
      _ -> raw
    end
  end

  defp maybe_strip_frontmatter(raw, false), do: raw

  defp render_html(markdown, %{adapter: :mdex} = config) do
    if Code.ensure_loaded?(Mdex) and function_exported?(Mdex, :to_html, 1) do
      html = apply(Mdex, :to_html, [markdown])
      {:ok, html, :mdex, []}
    else
      {:ok, html, :simple, diagnostics} = simple_render(markdown, config)

      warning =
        diagnostic(
          :warning,
          "mdex unavailable; using simple renderer",
          nil,
          "Add mdex dependency for full markdown fidelity",
          :mdex_unavailable
        )

      {:ok, html, :simple, [warning | diagnostics]}
    end
  end

  defp render_html(markdown, %{adapter: :simple} = config) do
    simple_render(markdown, config)
  end

  defp render_html(markdown, %{adapter: :auto} = config) do
    if Code.ensure_loaded?(Mdex) and function_exported?(Mdex, :to_html, 1) do
      render_html(markdown, %{config | adapter: :mdex})
    else
      render_html(markdown, %{config | adapter: :simple})
    end
  end

  defp render_html(_markdown, %{adapter: adapter}) do
    {:error, Error.new(:render_failed, "unsupported renderer adapter", %{adapter: adapter})}
  end

  defp simple_render(markdown, config) do
    lines = String.split(markdown, "\n", trim: false)
    heading_ids = heading_index(markdown)

    {html_lines, diagnostics, _fence_state} =
      Enum.reduce(Enum.with_index(lines, 1), {[], [], :outside}, fn {line, line_no},
                                                                    {acc_html, acc_diag,
                                                                     fence_state} ->
        case {fence_state, parse_fence(line)} do
          {:outside, :toggle} ->
            {["<pre><code>" | acc_html], acc_diag, {:inside, "text"}}

          {:outside, {:open, lang}} ->
            {tag, diag} = code_tag_for(lang, config, line_no)
            {["<pre><code#{tag}>" | acc_html], maybe_prepend(diag, acc_diag), {:inside, lang}}

          {{:inside, _lang}, :toggle} ->
            {["</code></pre>" | acc_html], acc_diag, :outside}

          {{:inside, _lang}, _} ->
            {[escape_html(line) | acc_html], acc_diag, fence_state}

          {:outside, _} ->
            {rendered, diag} = line_to_html(line, line_no, heading_ids)
            {[rendered | acc_html], maybe_prepend(diag, acc_diag), :outside}
        end
      end)

    {:ok, Enum.reverse(html_lines) |> Enum.join("\n"), :simple, Enum.reverse(diagnostics)}
  end

  defp parse_fence(line) do
    if String.trim(line) == "```" do
      :toggle
    else
      case Regex.run(~r/^```\s*([a-zA-Z0-9_-]+)?\s*$/, line) do
        [_, lang] when is_binary(lang) and lang != "" -> {:open, String.downcase(lang)}
        [_, _] -> {:open, "text"}
        nil -> :none
      end
    end
  end

  defp code_tag_for(lang, config, line_no) do
    syntax = config.syntax_highlight

    if syntax.enabled do
      supported = lang in syntax.supported_languages

      if supported do
        {" class=\"language-#{lang} theme-#{syntax.theme}\"", nil}
      else
        {
          " class=\"language-text theme-#{syntax.theme}\"",
          diagnostic(
            :warning,
            "unsupported code language '#{lang}', falling back to plaintext",
            %{line: line_no},
            "Use a supported language id or extend supported_languages",
            :unsupported_code_language
          )
        }
      end
    else
      {"", nil}
    end
  end

  defp line_to_html("", _line_no, _heading_ids), do: {"", nil}

  defp line_to_html(line, line_no, heading_ids) do
    cond do
      Regex.match?(~r/^(#+)\s+(.+)$/, line) ->
        [_, hashes, title] = Regex.run(~r/^(#+)\s+(.+)$/, line)
        level = String.length(hashes)
        id = Map.get(heading_ids, line_no, heading_id(title, %{}) |> elem(0))

        {
          "<h#{level} id=\"#{id}\">#{escape_html(String.trim(title))}</h#{level}>",
          nil
        }

      Regex.match?(~r/^[-*+]\s+.+$/, line) ->
        {"<li>#{escape_html(Regex.replace(~r/^[-*+]\s+/, line, ""))}</li>", nil}

      Regex.match?(~r/^\|.+\|$/, line) ->
        {"<p class=\"md-table-row\">#{escape_html(line)}</p>", nil}

      String.contains?(line, "[") and String.contains?(line, "](") ->
        {"<p>#{linkify(line)}</p>", nil}

      true ->
        {"<p>#{escape_html(line)}</p>", nil}
    end
  rescue
    _ ->
      {
        "<p>#{escape_html(line)}</p>",
        diagnostic(
          :warning,
          "line-level render fallback used",
          %{line: line_no},
          "Check markdown syntax on this line",
          :line_fallback
        )
      }
  end

  defp extract_headings(markdown) do
    {toc, _counts} =
      markdown
      |> String.split("\n", trim: false)
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{}}, fn {line, line_no}, {acc, counts} ->
        case Regex.run(~r/^(#+)\s+(.+)$/, line) do
          [_, hashes, title] ->
            level = String.length(hashes)
            {id, next_counts} = heading_id(title, counts)

            entry = %{
              level: level,
              id: id,
              href: "##{id}",
              title: String.trim(title),
              line: line_no
            }

            {[entry | acc], next_counts}

          _ ->
            {acc, counts}
        end
      end)

    Enum.reverse(toc)
  end

  defp heading_index(markdown) do
    markdown
    |> extract_headings()
    |> Map.new(fn heading -> {heading.line, heading.id} end)
  end

  defp heading_id(title, counts) do
    base =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.trim()
      |> String.replace(~r/\s+/, "-")
      |> case do
        "" -> "section"
        value -> value
      end

    count = Map.get(counts, base, 0)

    id = if count == 0, do: base, else: base <> "-" <> Integer.to_string(count + 1)
    {id, Map.put(counts, base, count + 1)}
  end

  defp linkify(line) do
    Regex.replace(~r/\[([^\]]+)\]\(([^\)]+)\)/, escape_html(line), "<a href=\"\\2\">\\1</a>")
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp diagnostic(severity, message, location, hint, code) do
    %{severity: severity, message: message, location: location, hint: hint, code: code}
  end

  defp maybe_prepend(nil, list), do: list
  defp maybe_prepend(item, list), do: [item | list]

  defp deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, a, b ->
      if is_map(a) and is_map(b) do
        deep_merge(a, b)
      else
        b
      end
    end)
  end
end
