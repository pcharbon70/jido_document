defmodule JidoDocs.Render.ThemeRegistry do
  @moduledoc """
  Theme registry abstraction for syntax-highlighting configuration.
  """

  @default_theme "onedark"

  @themes %{
    "onedark" => %{name: "One Dark", contrast: :high},
    "github" => %{name: "GitHub", contrast: :medium},
    "monokai" => %{name: "Monokai", contrast: :high},
    "solarized-light" => %{name: "Solarized Light", contrast: :medium},
    "solarized-dark" => %{name: "Solarized Dark", contrast: :medium}
  }

  @spec default_theme() :: String.t()
  def default_theme, do: @default_theme

  @spec known_themes() :: [String.t()]
  def known_themes do
    @themes |> Map.keys() |> Enum.sort()
  end

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(theme) when is_binary(theme) do
    case Map.get(@themes, theme) do
      nil -> :error
      metadata -> {:ok, Map.put(metadata, :id, theme)}
    end
  end

  @spec normalize(String.t()) :: {:ok, String.t()} | {:error, String.t(), [String.t()]}
  def normalize(theme) when is_binary(theme) do
    case fetch(theme) do
      {:ok, _} -> {:ok, theme}
      :error -> {:error, @default_theme, known_themes()}
    end
  end
end
