defmodule GameServerWeb.Api.V1.Admin.SessionController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import Ecto.Query

  alias GameServer.Accounts
  alias GameServer.Accounts.UserToken
  alias GameServer.Repo
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Admin – Sessions"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @session_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      user_email: %Schema{type: :string},
      context: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: "date-time"},
      authenticated_at: %Schema{type: :string, format: "date-time", nullable: true}
    }
  }

  @meta_schema %Schema{
    type: :object,
    properties: %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      count: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      has_more: %Schema{type: :boolean}
    }
  }

  operation(:index,
    operation_id: "admin_list_sessions",
    summary: "List sessions (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok:
        {"Sessions (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{data: %Schema{type: :array, items: @session_schema}, meta: @meta_schema}
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    {page, page_size} = GameServerWeb.Pagination.params(params)

    total_count = Repo.aggregate(from(t in UserToken, where: t.context == "session"), :count)

    tokens =
      Repo.all(
        from t in UserToken,
          join: u in assoc(t, :user),
          where: t.context == "session",
          order_by: [desc: t.inserted_at],
          offset: ^((page - 1) * page_size),
          limit: ^page_size,
          preload: [user: u]
      )

    json(conn, %{
      data: Enum.map(tokens, &serialize_session/1),
      meta: Pagination.meta(page, page_size, length(tokens), total_count)
    })
  end

  operation(:delete,
    operation_id: "admin_delete_session",
    summary: "Delete session token by id (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Repo.get(UserToken, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      %UserToken{} = token ->
        case Accounts.delete_user_token(token) do
          {:ok, _} ->
            json(conn, %{})

          {:error, %Ecto.Changeset{} = cs} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "validation_failed",
              errors: Ecto.Changeset.traverse_errors(cs, & &1)
            })
        end
    end
  end

  operation(:delete_user_sessions,
    operation_id: "admin_delete_user_sessions",
    summary: "Delete all session tokens for a user (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def delete_user_sessions(conn, %{"id" => id}) do
    user_id = id

    _ =
      Repo.delete_all(
        from(t in UserToken, where: t.user_id == ^user_id and t.context == "session")
      )

    json(conn, %{})
  end

  defp serialize_session(token) do
    %{
      id: token.id,
      user_id: token.user_id,
      username: (token.user && token.user.username) || "",
      display_name: (token.user && token.user.display_name) || "",
      user_email: (token.user && token.user.email) || "",
      context: token.context || "",
      inserted_at: token.inserted_at,
      authenticated_at: token.authenticated_at
    }
  end
end
