---
name: code-review
description: Review changed files
model: sonnet
allowed-tools:
  - Read
  - Grep
  - Bash(git diff:*)
jido:
  command_module: Jido.Code.Command.Commands.CodeReview
  hooks:
    pre: true
    after: true
  schema:
    target_file:
      type: string
      required: true
      doc: File path to review
    mode:
      type: atom
      default: standard
---
Review {{target_file}} using mode {{mode}} and summarize findings.

