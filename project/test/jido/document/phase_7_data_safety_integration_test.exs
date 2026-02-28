defmodule Jido.Document.Phase7DataSafetyIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.Agent

  setup do
    uniq = Integer.to_string(System.unique_integer([:positive]))
    session_id = "phase7-safety-" <> uniq

    {:ok, agent} = Agent.start_link(session_id: session_id)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase7_safety_" <> uniq)
    File.mkdir_p!(tmp_dir)

    source_path = Path.join(tmp_dir, "source.md")
    File.write!(source_path, "---\ntitle: \"Safety\"\n---\nBody 0\n")

    on_exit(fn ->
      if Process.alive?(agent) do
        _ = catch_exit(GenServer.stop(agent, :normal))
      end

      File.rm_rf(tmp_dir)
    end)

    %{agent: agent, source_path: source_path}
  end

  test "masks sensitive values in preview while preserving raw document body", ctx do
    token = "jido_secret_abcdefghijklmnopqrstuvwx"
    body = "Public text\n\nToken: #{token}\n"

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, load_opts())
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: body})

    assert %{status: :ok, value: %{preview: preview}} =
             Agent.command(
               ctx.agent,
               :render,
               %{safety: %{approved_codes: []}}
             )

    assert String.contains?(preview.html, "[REDACTED:api_token]")
    refute String.contains?(preview.html, token)
    assert get_in(preview, [:metadata, :safety, :redacted]) == true
    assert length(get_in(preview, [:metadata, :safety, :findings])) >= 1

    state = Agent.state(ctx.agent)
    assert String.contains?(state.document.body, token)
  end

  test "save policy blocks unapproved sensitive content and allows approved exceptions", ctx do
    token = "jido_secret_abcdefghijklmnopqrstuvwxyz01234"
    body = "Token: #{token}\n"

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, load_opts())
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: body})

    assert %{status: :error, error: blocked} =
             Agent.command(
               ctx.agent,
               :save,
               %{path: ctx.source_path, safety: %{}},
               load_opts()
             )

    assert blocked.code == :validation_failed
    assert blocked.details.policy == :sensitive_content

    assert %{status: :ok} =
             Agent.command(
               ctx.agent,
               :save,
               %{path: ctx.source_path, safety: %{approved_codes: ["api_token"]}},
               load_opts()
             )

    assert String.contains?(File.read!(ctx.source_path), token)
  end

  test "supports custom detector plugins for domain-specific safety policies", ctx do
    body = "Record: PII-123-45-6789\n"

    detector = fn content ->
      case :binary.match(content, "PII-123-45-6789") do
        {index, length} ->
          [
            %{
              code: "pii_custom",
              severity: :high,
              index: index,
              length: length,
              message: "Custom PII detector matched"
            }
          ]

        :nomatch ->
          []
      end
    end

    assert %{status: :ok} = Agent.command(ctx.agent, :load, %{path: ctx.source_path}, load_opts())
    assert %{status: :ok} = Agent.command(ctx.agent, :update_body, %{body: body})

    assert %{status: :ok, value: %{preview: preview}} =
             Agent.command(
               ctx.agent,
               :render,
               %{safety: %{detectors: [detector]}}
             )

    assert String.contains?(preview.html, "[REDACTED:pii_custom]")
    assert Enum.any?(preview.diagnostics, fn diag -> diag.code == :sensitive_content end)
  end

  defp load_opts, do: [context_options: %{workspace_root: "/"}]
end
