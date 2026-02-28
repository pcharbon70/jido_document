# Phase 2 - Document Model, Frontmatter, and Schema

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoDocs.Document`
- `JidoDocs.Schema`
- `JidoDocs.Field`
- Frontmatter parser adapter behavior

## Relevant Assumptions / Defaults
- Frontmatter supports YAML (`---`) and TOML (`+++`).
- Document API is pure and UI-agnostic.
- Validation returns structured errors with field paths.

[x] 2 Phase 2 - Document Model, Frontmatter, and Schema  
Description: Build the canonical document representation with deterministic parse, serialize, and validation behavior.

 [x] 2.1 Section - Document Struct and Invariants  
 Description: Define the core data model and enforce internal consistency rules.

  [x] 2.1.1 Task - Implement `JidoDocs.Document` struct contract  
  Description: Introduce the canonical runtime shape for document state.
   [x] 2.1.1.1 Subtask - Define fields (`path`, `frontmatter`, `body`, `raw`, `schema`, `dirty`, `revision`).  
   Description: Support editing, rendering, and persistence needs.
   [x] 2.1.1.2 Subtask - Add type specs and constructor helpers.  
   Description: Ensure compile-time clarity and consistent instantiation.
   [x] 2.1.1.3 Subtask - Define `dirty` and `revision` semantics.  
   Description: Keep mutation tracking explicit and predictable.

  [x] 2.1.2 Task - Implement invariant validation helpers  
  Description: Prevent invalid document states from propagating.
   [x] 2.1.2.1 Subtask - Validate required fields and types.  
   Description: Reject malformed maps and unsupported values.
   [x] 2.1.2.2 Subtask - Validate schema compatibility assumptions.  
   Description: Ensure document frontmatter aligns with active schema contract.
   [x] 2.1.2.3 Subtask - Add invariant guard entrypoints.  
   Description: Reuse checks across parse, update, and save flows.

 [x] 2.2 Section - Frontmatter Parsing and Serialization  
 Description: Implement robust handling for delimiter detection, parse, and roundtrip output.

  [x] 2.2.1 Task - Implement frontmatter splitting and syntax detection  
  Description: Reliably separate frontmatter and markdown body content.
   [x] 2.2.1.1 Subtask - Detect YAML/TOML delimiters at file start.  
   Description: Avoid false positives for delimiter-like body text.
   [x] 2.2.1.2 Subtask - Handle files without frontmatter.  
   Description: Return empty metadata map and preserve body content.
   [x] 2.2.1.3 Subtask - Handle malformed delimiter scenarios.  
   Description: Return parse errors with location context.

  [x] 2.2.2 Task - Implement frontmatter parse and serialize pipeline  
  Description: Support deterministic map conversion and output generation.
   [x] 2.2.2.1 Subtask - Parse YAML/TOML strings into maps via adapters.  
   Description: Normalize parser output to a stable internal shape.
   [x] 2.2.2.2 Subtask - Serialize maps with consistent formatting rules.  
   Description: Produce stable text output for repeatable diffs.
   [x] 2.2.2.3 Subtask - Implement parse/serialize roundtrip checks.  
   Description: Ensure no silent loss of supported metadata fields.

 [x] 2.3 Section - Schema and Field Definition System  
 Description: Provide schema-driven metadata definitions for validation and UI generation.

  [x] 2.3.1 Task - Implement `JidoDocs.Schema` behavior and `JidoDocs.Field` struct  
  Description: Define declarative field contracts that adapters can consume.
   [x] 2.3.1.1 Subtask - Add field attributes (`name`, `type`, `label`, `required`, `default`, `options`).  
   Description: Capture enough information for both runtime validation and form rendering.
   [x] 2.3.1.2 Subtask - Add primitive and composite type support.  
   Description: Support `:string`, `:integer`, `:boolean`, arrays, and enums.
   [x] 2.3.1.3 Subtask - Support custom validator hooks.  
   Description: Allow domain-specific constraints beyond type checks.

  [x] 2.3.2 Task - Implement schema validation engine  
  Description: Validate frontmatter maps against schema definitions with precise errors.
   [x] 2.3.2.1 Subtask - Add type coercion where safe and explicit.  
   Description: Convert compatible scalar values while flagging ambiguous cases.
   [x] 2.3.2.2 Subtask - Aggregate field-level errors with paths.  
   Description: Return structured diagnostics for UI and API consumers.
   [x] 2.3.2.3 Subtask - Emit unknown/extra key diagnostics policy.  
   Description: Configure warn, ignore, or reject behavior.

 [x] 2.4 Section - Mutation and Canonicalization Utilities  
 Description: Ensure edits produce stable document states and output diffs.

  [x] 2.4.1 Task - Implement document mutation helpers  
  Description: Update frontmatter and body while preserving invariants.
   [x] 2.4.1.1 Subtask - Add frontmatter merge/replace operations.  
   Description: Support partial updates from form controls.
   [x] 2.4.1.2 Subtask - Add body replacement and patch application helpers.  
   Description: Allow full-text and diff-based update flows.
   [x] 2.4.1.3 Subtask - Ensure mutation updates `dirty` and `revision`.  
   Description: Keep state change tracking reliable.

  [x] 2.4.2 Task - Implement canonicalization rules  
  Description: Normalize document output for stable persistence and comparison.
   [x] 2.4.2.1 Subtask - Normalize line endings and trailing whitespace policy.  
   Description: Avoid platform-dependent output drift.
   [x] 2.4.2.2 Subtask - Normalize frontmatter key ordering policy.  
   Description: Make serialized output deterministic for review and diffing.
   [x] 2.4.2.3 Subtask - Preserve body content fidelity.  
   Description: Ensure canonicalization does not alter markdown meaning.

 [x] 2.5 Section - Phase 2 Integration Tests  
 Description: Validate parse, serialize, schema, and mutation behavior end-to-end.

  [x] 2.5.1 Task - Document parse/serialize integration tests  
  Description: Verify robust behavior across syntax variants and malformed input.
   [x] 2.5.1.1 Subtask - Test YAML, TOML, and no-frontmatter cases.  
   Description: Ensure correct split and metadata extraction.
   [x] 2.5.1.2 Subtask - Test malformed delimiter and parser errors.  
   Description: Verify actionable diagnostics are returned.
   [x] 2.5.1.3 Subtask - Test deterministic roundtrip output.  
   Description: Assert stable serialization after repeated load/save cycles.

  [x] 2.5.2 Task - Schema and mutation integration tests  
  Description: Validate update flows and schema constraints together.
   [x] 2.5.2.1 Subtask - Test valid and invalid field updates.  
   Description: Confirm expected coercion and errors.
   [x] 2.5.2.2 Subtask - Test unknown key policy behavior.  
   Description: Validate warn/ignore/reject modes.
   [x] 2.5.2.3 Subtask - Test revision and dirty-state transitions.  
   Description: Ensure mutation tracking is consistent.
