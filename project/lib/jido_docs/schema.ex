defmodule JidoDocs.Schema do
  @moduledoc """
  Schema behavior contract used to validate frontmatter against a field model.

  Field-level validation is implemented in Phase 2 Section 2.3.
  """

  @callback fields() :: list()
end
