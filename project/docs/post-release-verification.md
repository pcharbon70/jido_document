# Post-Release Verification

This checklist covers first-day operational validation after a release.

## 1. First-day telemetry and error budgets

- Confirm command telemetry events are emitted for core actions:
  `load`, `update_frontmatter`, `update_body`, `render`, `save`.
- Track first-day error budget:
  - target: <= 5% command error rate,
  - block escalation when error rate exceeds threshold for sustained windows.
- Export audit traces for failed sessions to support incident triage.

## 2. Documentation and sample command validation

Run documented examples:

```bash
mix run examples/minimal_api_sample.exs
mix run examples/session_concurrency_sample.exs
mix run examples/crash_recovery_sample.exs
```

## 3. Issue intake and triage loop

Prepare release feedback list in `issues.exs`:

```elixir
[
  %{id: "REL-1", summary: "Save conflict under load", severity: :high, frequency: 6, reproducible: true},
  %{id: "REL-2", summary: "Docs typo", severity: :low, frequency: 1, reproducible: true}
]
```

Generate prioritized triage output:

```bash
mix jido.triage_report --input ./issues.exs --output ./triage.md --min-score 20
```

Use the output as the source for post-release follow-up planning.
