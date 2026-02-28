# Contribution and Review Guidelines

This document defines quality expectations for changes to `jido_document`.

## Required contribution checklist

1. Scope clarity
   - State the problem and expected behavior changes.
   - Explicitly call out any semver impact.
2. Tests
   - Add or update unit/integration/property tests as needed.
   - Cover failure paths, not only happy paths.
3. Documentation
   - Update guides and API docs for behavior or contract changes.
4. Validation
   - Run `mix quality` locally before opening a pull request.

## Review checklist

1. Correctness and safety
   - Path safety, frontmatter parsing behavior, and persistence guarantees.
2. Backward compatibility
   - Stable API impact is intentional and documented.
3. Operational behavior
   - Errors are structured, actionable, and auditable.
4. Readability and maintainability
   - Keep modules focused and avoid hidden coupling.

## Merge gates

- CI must pass on all configured matrix targets.
- Public API manifest checks must pass.
- Critical review findings must be resolved before merge.
