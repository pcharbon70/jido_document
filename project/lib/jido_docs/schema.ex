defmodule JidoDocs.Schema do
  @moduledoc """
  Schema behavior for frontmatter field definitions.
  """

  @callback fields() :: list()
end
