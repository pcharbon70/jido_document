defmodule JidoDocs.Error do
  @moduledoc """
  Normalized domain error taxonomy for JidoDocs actions and agent workflows.
  """

  @typedoc "Canonical machine-readable reason codes."
  @type code ::
          :invalid_params
          | :parse_failed
          | :validation_failed
          | :filesystem_error
          | :render_failed
          | :not_found
          | :conflict
          | :busy
          | :subscription_error
          | :internal

  @typedoc "High-level category used for grouping and diagnostics."
  @type category :: :input | :parsing | :validation | :io | :render | :lifecycle | :system

  @type t :: %__MODULE__{
          code: code(),
          category: category(),
          message: String.t(),
          details: map(),
          retryable: boolean()
        }

  defstruct [:code, :category, :message, details: %{}, retryable: false]

  @spec new(code(), String.t(), map()) :: t()
  def new(code, message, details \\ %{}) do
    %__MODULE__{
      code: code,
      category: category_for(code),
      message: message,
      details: details,
      retryable: retryable?(code)
    }
  end

  @spec from_reason(term(), map()) :: t()
  def from_reason(reason, details \\ %{})

  def from_reason(%__MODULE__{} = error, details) do
    merge_details(error, details)
  end

  def from_reason({:error, reason}, details), do: from_reason(reason, details)

  def from_reason({:invalid, message}, details) when is_binary(message) do
    new(:validation_failed, message, details)
  end

  def from_reason({:parse, reason}, details) do
    new(:parse_failed, "Parse failure: #{inspect(reason)}", Map.put(details, :reason, reason))
  end

  def from_reason({:filesystem, reason}, details) do
    new(
      :filesystem_error,
      "Filesystem failure: #{inspect(reason)}",
      Map.put(details, :reason, reason)
    )
  end

  def from_reason({:render, reason}, details) do
    new(:render_failed, "Render failure: #{inspect(reason)}", Map.put(details, :reason, reason))
  end

  def from_reason(:enoent, details), do: new(:not_found, "Resource not found", details)
  def from_reason(:busy, details), do: new(:busy, "Operation is currently busy", details)
  def from_reason(:conflict, details), do: new(:conflict, "Operation conflict", details)

  def from_reason(reason, details) when is_binary(reason) do
    new(:internal, reason, details)
  end

  def from_reason(reason, details) do
    new(
      :internal,
      "Unhandled error reason: #{inspect(reason)}",
      Map.put(details, :reason, reason)
    )
  end

  @spec from_exception(Exception.t(), map()) :: t()
  def from_exception(%File.Error{} = exception, details) do
    code = if exception.reason == :enoent, do: :not_found, else: :filesystem_error

    new(
      code,
      Exception.message(exception),
      Map.merge(details, %{exception: exception.__struct__, reason: exception.reason})
    )
  end

  def from_exception(%ArgumentError{} = exception, details) do
    new(
      :invalid_params,
      Exception.message(exception),
      Map.put(details, :exception, exception.__struct__)
    )
  end

  def from_exception(exception, details) do
    new(
      :internal,
      Exception.message(exception),
      Map.put(details, :exception, exception.__struct__)
    )
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      code: error.code,
      category: error.category,
      message: error.message,
      details: error.details,
      retryable: error.retryable
    }
  end

  @spec merge_details(t(), map()) :: t()
  def merge_details(%__MODULE__{} = error, details) when is_map(details) do
    %{error | details: Map.merge(error.details, details)}
  end

  @spec category_for(code()) :: category()
  def category_for(:invalid_params), do: :input
  def category_for(:parse_failed), do: :parsing
  def category_for(:validation_failed), do: :validation
  def category_for(:filesystem_error), do: :io
  def category_for(:render_failed), do: :render
  def category_for(:not_found), do: :io
  def category_for(:conflict), do: :lifecycle
  def category_for(:busy), do: :lifecycle
  def category_for(:subscription_error), do: :lifecycle
  def category_for(:internal), do: :system

  @spec retryable?(code()) :: boolean()
  def retryable?(:busy), do: true
  def retryable?(:filesystem_error), do: true
  def retryable?(:render_failed), do: true
  def retryable?(_), do: false
end
