# JidoDocs Config Contract

This contract is implemented by `JidoDocs.Config` in Phase 1 Section 1.3.

## Precedence
1. Built-in defaults
2. Application config (`config :project, JidoDocs.Config, ...`)
3. Session options
4. Call options

## Parser defaults
- `default_syntax`: `:yaml`
- `supported_syntaxes`: `[:yaml, :toml]`
- `delimiters`: `%{yaml: "---", toml: "+++"}`

## Renderer defaults
- `adapter`: `JidoDocs.Adapters.Renderer.Mdex`
- `fallback_adapter`: `JidoDocs.Adapters.Renderer.Fallback`
- `debounce_ms`: `120`
- `timeout_ms`: `5000`
- `queue_limit`: `100`

## Persistence defaults
- `autosave_interval_ms`: `30000`
- `temp_dir`: `.jido_docs/tmp` (normalized under workspace root)
- `backup_extension`: `.bak`
- `atomic_writes`: `true`

## Validation errors
Validation returns `{:error, errors}` where each error includes:
- `path`: config key path (for example `[:renderer, :debounce_ms]`)
- `message`: human-readable issue
- `value`: rejected value
