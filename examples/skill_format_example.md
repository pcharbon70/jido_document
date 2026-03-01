---
name: pdf-processor
description: Extract text and tables from PDFs
version: 1.0.0
allowed-tools: Read, Write, Bash(python:*)
jido:
  actions:
    - MyApp.Actions.ExtractPdfText
    - MyApp.Actions.ExtractPdfTables
  router:
    - "pdf/extract/text": ExtractPdfText
    - "pdf/extract/tables": ExtractPdfTables
  hooks:
    pre:
      enabled: true
      signal_type: "skill/pdf_processor/pre"
      bus: ":jido_code_bus"
      data:
        source: "frontmatter"
    post:
      enabled: true
      signal_type: "skill/pdf_processor/post"
      bus: ":jido_code_bus"
      data:
        source: "frontmatter"
---
# PDF Processor

Use this skill to parse uploaded PDF files and return structured output:

- Extract plain text from each page.
- Extract table-like regions for downstream processing.
- Emit pre and post hook signals for observability.

