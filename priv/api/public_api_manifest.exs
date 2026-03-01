%{
  modules: [
    %{
      functions: [
        %{arity: 0, name: "start_session"},
        %{arity: 1, name: "start_session"}
      ],
      module: "Jido.Document"
    },
    %{
      functions: [
        %{arity: 2, name: "command"},
        %{arity: 3, name: "command"},
        %{arity: 4, name: "command"},
        %{arity: 1, name: "discard_recovery"},
        %{arity: 1, name: "export_trace"},
        %{arity: 2, name: "export_trace"},
        %{arity: 0, name: "list_recovery_candidates"},
        %{arity: 1, name: "list_recovery_candidates"},
        %{arity: 1, name: "recover"},
        %{arity: 2, name: "recover"},
        %{arity: 1, name: "recovery_status"},
        %{arity: 0, name: "start_link"},
        %{arity: 1, name: "start_link"},
        %{arity: 1, name: "state"},
        %{arity: 1, name: "subscribe"},
        %{arity: 2, name: "subscribe"},
        %{arity: 1, name: "unsubscribe"},
        %{arity: 2, name: "unsubscribe"}
      ],
      module: "Jido.Document.Agent"
    },
    %{
      functions: [
        %{arity: 2, name: "apply_body_patch"},
        %{arity: 3, name: "apply_body_patch"},
        %{arity: 0, name: "blank"},
        %{arity: 1, name: "blank"},
        %{arity: 1, name: "canonicalize"},
        %{arity: 2, name: "canonicalize"},
        %{arity: 1, name: "ensure_valid!"},
        %{arity: 1, name: "from_map"},
        %{arity: 1, name: "mark_clean"},
        %{arity: 1, name: "mark_dirty"},
        %{arity: 0, name: "new"},
        %{arity: 1, name: "new"},
        %{arity: 1, name: "parse"},
        %{arity: 2, name: "parse"},
        %{arity: 1, name: "serialize"},
        %{arity: 2, name: "serialize"},
        %{arity: 1, name: "touch"},
        %{arity: 2, name: "update_body"},
        %{arity: 3, name: "update_body"},
        %{arity: 2, name: "update_frontmatter"},
        %{arity: 3, name: "update_frontmatter"},
        %{arity: 1, name: "valid?"},
        %{arity: 1, name: "validate"}
      ],
      module: "Jido.Document.Document"
    },
    %{
      functions: [
        %{arity: 1, name: "delimiter_for"},
        %{arity: 2, name: "parse"},
        %{arity: 2, name: "serialize"},
        %{arity: 1, name: "split"}
      ],
      module: "Jido.Document.Frontmatter"
    },
    %{
      functions: [
        %{arity: 3, name: "cache_key"},
        %{arity: 2, name: "fallback_preview"},
        %{arity: 3, name: "fallback_preview"},
        %{arity: 1, name: "render"},
        %{arity: 2, name: "render"}
      ],
      module: "Jido.Document.Renderer"
    },
    %{
      functions: [
        %{arity: 2, name: "apply"},
        %{arity: 3, name: "apply"},
        %{arity: 2, name: "dry_run"}
      ],
      module: "Jido.Document.SchemaMigration"
    },
    %{
      functions: [
        %{arity: 2, name: "acquire_lock"},
        %{arity: 3, name: "acquire_lock"},
        %{arity: 4, name: "acquire_lock"},
        %{arity: 1, name: "ensure_session"},
        %{arity: 2, name: "ensure_session"},
        %{arity: 3, name: "ensure_session"},
        %{arity: 1, name: "ensure_session_by_path"},
        %{arity: 2, name: "ensure_session_by_path"},
        %{arity: 3, name: "ensure_session_by_path"},
        %{arity: 1, name: "fetch_session"},
        %{arity: 2, name: "fetch_session"},
        %{arity: 2, name: "force_takeover"},
        %{arity: 3, name: "force_takeover"},
        %{arity: 4, name: "force_takeover"},
        %{arity: 0, name: "list_sessions"},
        %{arity: 1, name: "list_sessions"},
        %{arity: 1, name: "reclaim_idle"},
        %{arity: 2, name: "reclaim_idle"},
        %{arity: 2, name: "release_lock"},
        %{arity: 3, name: "release_lock"},
        %{arity: 1, name: "session_id_for_path"},
        %{arity: 0, name: "start_link"},
        %{arity: 1, name: "start_link"},
        %{arity: 1, name: "touch"},
        %{arity: 2, name: "touch"},
        %{arity: 2, name: "validate_lock"},
        %{arity: 3, name: "validate_lock"}
      ],
      module: "Jido.Document.SessionRegistry"
    },
    %{
      functions: [
        %{arity: 3, name: "build"},
        %{arity: 4, name: "build"},
        %{arity: 0, name: "known_types"},
        %{arity: 1, name: "to_message"}
      ],
      module: "Jido.Document.Signal"
    },
    %{
      functions: [
        %{arity: 3, name: "broadcast"},
        %{arity: 4, name: "broadcast"},
        %{arity: 5, name: "broadcast"},
        %{arity: 0, name: "start_link"},
        %{arity: 1, name: "start_link"},
        %{arity: 1, name: "subscribe"},
        %{arity: 2, name: "subscribe"},
        %{arity: 3, name: "subscribe"},
        %{arity: 1, name: "subscribers"},
        %{arity: 2, name: "subscribers"},
        %{arity: 1, name: "unsubscribe"},
        %{arity: 2, name: "unsubscribe"},
        %{arity: 3, name: "unsubscribe"}
      ],
      module: "Jido.Document.SignalBus"
    }
  ],
  schema_version: 1,
  semver_policy: "docs/semver-policy.md",
  release_blocking_criteria: "docs/release-blocking-criteria.md"
}
