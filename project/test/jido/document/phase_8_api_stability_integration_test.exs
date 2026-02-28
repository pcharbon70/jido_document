defmodule Jido.Document.Phase8ApiStabilityIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Document.{Agent, PublicApi, SessionRegistry}

  test "public API manifest matches golden snapshot" do
    assert :ok = PublicApi.validate_contract()
    assert {:ok, expected} = PublicApi.read_manifest()
    assert expected == PublicApi.manifest_without_timestamp()
  end

  test "legacy call patterns remain compatible for core session workflows" do
    session_id = "phase8-api-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent} = Agent.start_link(session_id: session_id)

    tmp_dir = Path.join(System.tmp_dir!(), "jido_document_phase8_api_" <> session_id)
    File.mkdir_p!(tmp_dir)

    path = Path.join(tmp_dir, "doc.md")
    File.write!(path, "---\ntitle: \"Compat\"\n---\nBody\n")

    on_exit(fn ->
      if Process.alive?(agent) do
        _ = catch_exit(GenServer.stop(agent, :normal))
      end

      File.rm_rf(tmp_dir)
    end)

    # Legacy keyword context options and map params
    assert %{status: :ok} =
             Agent.command(agent, :load, %{path: path}, context_options: %{workspace_root: "/"})

    assert %{status: :ok} = Agent.command(agent, :update_body, %{body: "Updated body\n"})

    assert %{status: :ok} =
             Agent.command(agent, :save, %{path: path}, context_options: %{workspace_root: "/"})

    # Legacy session registry path lookup behavior remains available.
    assert {:ok, info} =
             SessionRegistry.ensure_session_by_path(SessionRegistry, path, workspace_root: "/")

    assert is_pid(info.pid)
  end

  test "stable modules expose baseline specs for key public functions" do
    assert has_spec?(Jido.Document, :start_session, 1)
    assert has_spec?(Jido.Document.Agent, :start_link, 1)
    assert has_spec?(Jido.Document.Agent, :command, 4)
    assert has_spec?(Jido.Document.Agent, :state, 1)
    assert has_spec?(Jido.Document.SessionRegistry, :ensure_session_by_path, 3)
    assert has_spec?(Jido.Document.Document, :parse, 2)
    assert has_spec?(Jido.Document.Renderer, :render, 2)
  end

  test "semantic versioning and release gate policy docs exist" do
    assert File.exists?("docs/public-api.md")
    assert File.exists?("docs/semver-policy.md")
    assert File.exists?("docs/release-blocking-criteria.md")
  end

  defp has_spec?(module, function, arity) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        Enum.any?(specs, fn
          {{name, found_arity}, _spec} -> name == function and found_arity == arity
          _ -> false
        end)

      :error ->
        false
    end
  end
end
