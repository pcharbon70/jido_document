defmodule JidoDocs.Renderer do
  @moduledoc """
  Renderer boundary for markdown preview generation.
  """

  @spec to_html(String.t()) :: {:error, :not_implemented}
  def to_html(_body), do: {:error, :not_implemented}
end
