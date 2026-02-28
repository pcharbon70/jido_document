defmodule JidoDocs.Document do
  @moduledoc """
  Canonical in-memory representation of a frontmatter + markdown document.

  Parsing and serialization behavior is introduced incrementally in later phases.
  """

  @type t :: %__MODULE__{
          path: Path.t() | nil,
          frontmatter: map(),
          body: String.t(),
          raw: String.t(),
          schema: module() | nil,
          dirty: boolean(),
          revision: non_neg_integer()
        }

  defstruct [
    :path,
    :schema,
    frontmatter: %{},
    body: "",
    raw: "",
    dirty: false,
    revision: 0
  ]
end
