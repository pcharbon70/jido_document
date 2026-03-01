# Plugin API Lifecycle Policy

This policy defines stability expectations for extension points used by
document processing plugins.

## Lifecycle states

1. Experimental
   - Not semver-stable.
   - May change in any minor release.
   - Must be documented as experimental in module docs.
2. Stable
   - Governed by semantic versioning.
   - Breaking changes require a major release.
   - Deprecations require at least one minor release overlap.
3. Deprecated
   - Marked with replacement guidance and removal target release.
   - Receives only compatibility and security fixes.
4. Removed
   - Removed in a major release after deprecation window completion.

## Compatibility guarantees

- Stable callbacks and contracts must keep argument/return compatibility across
  minor releases.
- New optional callbacks must include defaults or capability checks.
- Plugin execution failures must remain isolated from core document load/save
  workflows.

## Change control requirements

- Any lifecycle state transition requires:
  - Updated API docs.
  - Changelog entry.
  - Integration tests covering upgrade behavior.
- Deprecations must include explicit migration notes in release documentation.
