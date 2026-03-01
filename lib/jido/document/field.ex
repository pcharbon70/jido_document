defmodule Jido.Document.Field do
  @moduledoc """
  Declarative frontmatter field contract.
  """

  @type primitive_type :: :string | :integer | :float | :boolean
  @type field_type :: primitive_type() | {:array, primitive_type()} | {:enum, [term()]}

  @type validator :: (term() -> :ok | boolean() | {:error, String.t()})

  @type t :: %__MODULE__{
          name: atom(),
          type: field_type(),
          label: String.t() | nil,
          required: boolean(),
          default: term(),
          options: [term()],
          validator: validator() | nil
        }

  defstruct name: nil,
            type: :string,
            label: nil,
            required: false,
            default: nil,
            options: [],
            validator: nil
end
