defmodule Jido.Document.Authorization do
  @moduledoc """
  Action-level authorization policy checks.

  Authorization is opt-in per request by providing an `:authorization` policy
  inside action context options.
  """

  alias Jido.Document.{Action.Context, Error}

  @default_matrix %{
    read: ["viewer", "editor", "admin"],
    write: ["editor", "admin"],
    admin: ["admin"]
  }

  @spec authorize(atom(), map(), Context.t()) :: :ok | {:error, Error.t()}
  def authorize(action, params, %Context{} = context) when is_map(params) do
    case policy_from_context(context) do
      nil ->
        :ok

      policy ->
        required_permission = permission_for(action)
        actor = context.actor || %{}

        with :ok <- check_matrix(policy, required_permission, actor, action),
             :ok <- run_hook(policy, action, required_permission, actor, context, params) do
          :ok
        end
    end
  end

  @spec permission_for(atom()) :: :read | :write | :admin
  def permission_for(action) when action in [:load, :render], do: :read

  def permission_for(action)
      when action in [:update_frontmatter, :update_body, :save, :undo, :redo],
      do: :write

  def permission_for(_action), do: :admin

  defp policy_from_context(%Context{options: options}) do
    case Map.get(options, :authorization) do
      %{} = policy -> policy
      _ -> nil
    end
  end

  defp check_matrix(policy, required_permission, actor, action) do
    matrix = merge_matrix(policy)
    actor_roles = actor_roles(actor)
    allowed_roles = Map.get(matrix, required_permission, [])

    if actor_roles == [] do
      {:error,
       Error.new(:forbidden, "authorization denied", %{
         policy: :authorization,
         action: action,
         required_permission: required_permission,
         reason: :missing_roles,
         actor: actor_summary(actor)
       })}
    else
      if Enum.any?(actor_roles, &(&1 in allowed_roles)) do
        :ok
      else
        {:error,
         Error.new(:forbidden, "authorization denied", %{
           policy: :authorization,
           action: action,
           required_permission: required_permission,
           actor_roles: actor_roles,
           allowed_roles: allowed_roles,
           actor: actor_summary(actor)
         })}
      end
    end
  end

  defp run_hook(policy, action, required_permission, actor, context, params) do
    case Map.get(policy, :hook) do
      hook when is_function(hook, 5) ->
        case hook.(action, required_permission, actor, context, params) do
          :ok ->
            :ok

          {:error, %Error{} = error} ->
            {:error, error}

          {:error, reason} ->
            {:error,
             Error.from_reason(reason, %{
               policy: :authorization_hook,
               action: action,
               required_permission: required_permission
             })}

          other ->
            {:error,
             Error.new(:forbidden, "authorization hook rejected request", %{
               policy: :authorization_hook,
               action: action,
               required_permission: required_permission,
               response: other
             })}
        end

      _ ->
        :ok
    end
  end

  defp merge_matrix(policy) do
    policy_matrix =
      case Map.get(policy, :matrix) do
        %{} = matrix -> normalize_matrix(matrix)
        _ -> %{}
      end

    Map.merge(@default_matrix, policy_matrix)
  end

  defp normalize_matrix(matrix) do
    Enum.reduce(matrix, %{}, fn {permission, roles}, acc ->
      permission = normalize_permission(permission)

      if permission in [:read, :write, :admin] and is_list(roles) do
        Map.put(acc, permission, Enum.map(roles, &normalize_role/1))
      else
        acc
      end
    end)
  end

  defp normalize_permission(permission) when permission in [:read, :write, :admin], do: permission

  defp normalize_permission(permission) when is_binary(permission) do
    case permission do
      "read" -> :read
      "write" -> :write
      "admin" -> :admin
      _ -> :unknown
    end
  end

  defp normalize_permission(_), do: :unknown

  defp actor_roles(actor) when is_map(actor) do
    case Map.get(actor, :roles) || Map.get(actor, "roles") do
      roles when is_list(roles) -> Enum.map(roles, &normalize_role/1)
      _ -> []
    end
  end

  defp actor_roles(_), do: []

  defp normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  defp normalize_role(role) when is_binary(role), do: role
  defp normalize_role(role), do: to_string(role)

  defp actor_summary(actor) when is_map(actor) do
    %{
      id: Map.get(actor, :id) || Map.get(actor, "id"),
      roles: actor_roles(actor)
    }
  end

  defp actor_summary(_), do: %{id: nil, roles: []}
end
