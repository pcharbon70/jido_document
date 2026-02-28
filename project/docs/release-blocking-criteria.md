# Release Blocking Criteria

A release candidate is blocked when any of the following fails:

1. API contract checks:
   - `mix jido.api_manifest --check` must pass.
   - No unreviewed drift in stable public modules or function signatures.
2. Test and quality checks:
   - `mix test` must pass.
   - `mix format --check-formatted` must pass.
   - `mix compile --warnings-as-errors` must pass.
3. Compatibility checks:
   - Backward-compatibility integration suite must pass.
   - Migration tooling dry-run checks must pass for representative fixtures.
4. Documentation checks:
   - Quickstart and example commands must execute successfully.
   - Semver and release note updates must be present for behavior changes.
5. Security and reliability checks:
   - No high-severity secret scanning or policy violations in release artifacts.
   - Circuit-breaker and degraded-mode integration checks must pass.

A release can proceed only when all blocking criteria are green.
