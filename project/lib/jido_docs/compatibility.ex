defmodule JidoDocs.Compatibility do
  @moduledoc """
  Dependency capability checks with optional compile-time enforcement.
  """

  alias JidoDocs.{DependencyMatrix, Error}

  @after_compile __MODULE__
  @enforce_dependency_checks Application.compile_env(:project, :enforce_dependency_checks, false)

  @type check_result :: :ok | {:error, [Error.t()]}

  @spec check(keyword()) :: check_result()
  def check(opts \\ []) do
    strict? = Keyword.get(opts, :strict, true)

    errors =
      DependencyMatrix.requirements()
      |> Enum.filter(&(strict? or &1.type == :required))
      |> Enum.reduce([], fn requirement, acc ->
        if Code.ensure_loaded?(requirement.module) do
          acc
        else
          [
            Error.new(
              :dependency_missing,
              "Missing dependency module #{inspect(requirement.module)}",
              Map.take(requirement, [:app, :capability, :min_version, :type])
            )
            | acc
          ]
        end
      end)
      |> Enum.reverse()

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc false
  def __after_compile__(_env, _bytecode) do
    if @enforce_dependency_checks do
      case check(strict: true) do
        :ok ->
          :ok

        {:error, errors} ->
          message =
            errors
            |> Enum.map_join("\n", fn error ->
              "- #{error.message} (#{inspect(error.details)})"
            end)

          raise CompileError,
            description: "JidoDocs dependency checks failed:\n#{message}"
      end
    end
  end
end
