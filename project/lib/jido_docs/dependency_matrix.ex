defmodule JidoDocs.DependencyMatrix do
  @moduledoc """
  Baseline dependency compatibility matrix and policy metadata.
  """

  @type dependency_type :: :required | :optional

  @type requirement :: %{
          type: dependency_type(),
          app: atom(),
          min_version: String.t(),
          module: module(),
          capability: atom(),
          rationale: String.t()
        }

  @requirements [
    %{
      type: :required,
      app: :jido,
      min_version: "~> 1.0",
      module: Jido.Agent,
      capability: :orchestration,
      rationale: "Session orchestration and core agent behavior"
    },
    %{
      type: :required,
      app: :jido_action,
      min_version: "~> 1.0",
      module: Jido.Action,
      capability: :actions,
      rationale: "Atomic action contracts and execution"
    },
    %{
      type: :required,
      app: :jido_signal,
      min_version: "~> 1.0",
      module: Jido.Signal,
      capability: :signals,
      rationale: "Signal/event contracts for session synchronization"
    },
    %{
      type: :required,
      app: :mdex,
      min_version: "~> 0.9",
      module: Mdex,
      capability: :rendering,
      rationale: "Markdown rendering pipeline"
    },
    %{
      type: :optional,
      app: :yaml_elixir,
      min_version: "~> 2.11",
      module: YamlElixir,
      capability: :yaml_frontmatter,
      rationale: "YAML frontmatter parser adapter"
    },
    %{
      type: :optional,
      app: :toml,
      min_version: "~> 0.7",
      module: Toml,
      capability: :toml_frontmatter,
      rationale: "TOML frontmatter parser adapter"
    }
  ]

  @spec requirements() :: [requirement()]
  def requirements, do: @requirements

  @spec required_requirements() :: [requirement()]
  def required_requirements do
    Enum.filter(@requirements, &(&1.type == :required))
  end

  @spec optional_requirements() :: [requirement()]
  def optional_requirements do
    Enum.filter(@requirements, &(&1.type == :optional))
  end
end
