# Dependency Compatibility Policy

This document captures the Phase 1 compatibility policy and baseline versions.

## Required dependencies
- `jido` `~> 1.0`: session orchestration and agent behavior.
- `jido_action` `~> 1.0`: atomic action execution contracts.
- `jido_signal` `~> 1.0`: event/signal contracts.
- `mdex` `~> 0.9`: markdown rendering.

## Optional dependencies
- `yaml_elixir` `~> 2.11`: YAML frontmatter parser adapter.
- `toml` `~> 0.7`: TOML frontmatter parser adapter.

## Enforcement policy
- Runtime: `JidoDocs.Compatibility.check/1` validates required modules by default.
- Compile-time: set `config :project, :enforce_dependency_checks, true` to fail compilation when required capabilities are missing.
- Adapter fallback: when a parser or renderer dependency is unavailable, adapters return normalized `JidoDocs.Error` values.
