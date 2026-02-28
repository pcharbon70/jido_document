defmodule JidoDocs.Phase1ContractIntegrationTest do
  use ExUnit.Case, async: false

  test "frontmatter adapter normalizes missing dependency failures" do
    assert {:error, error} = JidoDocs.Adapters.Frontmatter.parse(:yaml, "title: hello")

    assert %JidoDocs.Error{} = error
    assert error.code == :parser_unavailable
    assert error.details.syntax == :yaml
    assert error.details.adapter == JidoDocs.Adapters.Frontmatter.Yaml
  end

  test "config normalization returns structured path-aware errors" do
    assert {:error, errors} =
             JidoDocs.Config.normalize(%{
               parser: %{default_syntax: :invalid},
               renderer: %{debounce_ms: -1},
               persistence: %{atomic_writes: :sometimes},
               workspace_root: 99
             })

    error_paths = Enum.map(errors, & &1.path)

    assert [:workspace_root] in error_paths
    assert [:parser, :default_syntax] in error_paths
    assert [:renderer, :debounce_ms] in error_paths
    assert [:persistence, :atomic_writes] in error_paths
  end

  test "compatibility checks produce clear diagnostics for missing required dependencies" do
    assert {:error, errors} = JidoDocs.Compatibility.check(strict: true)

    assert Enum.any?(errors, fn error ->
             error.code == :dependency_missing and error.details.app == :jido
           end)

    assert Enum.any?(errors, fn error ->
             error.code == :dependency_missing and error.details.app == :mdex
           end)
  end

  test "compatibility checks still validate required dependencies when optional checks are disabled" do
    assert {:error, errors} = JidoDocs.Compatibility.check(strict: false)

    assert Enum.all?(errors, fn error ->
             error.details.type == :required
           end)
  end
end
