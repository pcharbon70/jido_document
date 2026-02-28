defmodule JidoDocs.Action.Result do
  @moduledoc """
  Canonical action return contract with telemetry metadata.

  Metadata fields include:
  - `:action`
  - `:idempotency`
  - `:correlation_id`
  - `:duration_us`
  """

  alias JidoDocs.Error

  @type status :: :ok | :error

  @type t :: %__MODULE__{
          status: status(),
          value: term() | nil,
          error: Error.t() | nil,
          metadata: map()
        }

  defstruct status: :ok,
            value: nil,
            error: nil,
            metadata: %{}

  @spec ok(term(), map()) :: t()
  def ok(value, metadata \\ %{}) do
    %__MODULE__{status: :ok, value: value, metadata: metadata}
  end

  @spec error(Error.t(), map()) :: t()
  def error(%Error{} = error, metadata \\ %{}) do
    %__MODULE__{status: :error, error: error, metadata: metadata}
  end

  @spec unwrap(t()) :: {:ok, term(), map()} | {:error, Error.t(), map()}
  def unwrap(%__MODULE__{status: :ok, value: value, metadata: metadata}),
    do: {:ok, value, metadata}

  def unwrap(%__MODULE__{status: :error, error: error, metadata: metadata}),
    do: {:error, error, metadata}
end
