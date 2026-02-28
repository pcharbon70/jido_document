defmodule JidoDocs.Render.Plugin do
  @moduledoc """
  Plugin contract for markdown pre-render transforms.
  """

  @callback transform(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @callback compatible?(map()) :: boolean()
end
