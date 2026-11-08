defmodule GamendWeb.Api.V1.Admin.SessionController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.UserToken
  alias Gamend.Repo
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AdminSessionPage, OkResponse}
  alias OpenApiSpex.Schema

  require Gamend.Accounts.TokenContext, as: TokenContext

  tags(["Admin – Sessions"])

  operation(:index,
    operation_id: "admin_list_sessions",
    summary: "List sessions (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false]
    ],
    responses: [
      ok: {"Sessions, newest first", "application/json", AdminSessionPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)
    session_query = from(t in UserToken, where: t.context == ^TokenContext.session())

    total_count = Repo.aggregate(session_query, :count)

    tokens =
      from(t in session_query,
        join: u in assoc(t, :user),
        order_by: [desc: t.inserted_at],
        preload: [user: u]
      )
      |> Gamend.Query.page(page: page, page_size: page_size)
      |> Repo.all()

    reply_page(conn, Enum.map(tokens, &serialize_session/1), page, page_size, total_count)
  end

  operation(:delete,
    operation_id: "admin_delete_session",
    summary: "Delete session token by id (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      not_found: Schemas.error("Not found")
    ]
  )

  def delete(conn, %{"id" => id}) do
    case Repo.get_uuid(UserToken, id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      %UserToken{} = token ->
        case Accounts.delete_user_token(token) do
          {:ok, _} ->
            reply_ok(conn)

          # Signed out since it was read.
          {:error, :not_found} ->
            reply_error(conn, :not_found, "not_found")

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)
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
      ok: {"Deleted", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def delete_user_sessions(conn, %{"id" => id}) do
    # Revoke the JWTs as well as the browser sessions.
    #
    # Deleting `user_tokens` rows only ended browser sessions, so "revoke this
    # user's sessions" left every issued access and refresh token working —
    # up to the 30-day refresh TTL. `revoke_all_tokens/1` bumps `token_version`,
    # which is the claim `GamendWeb.Auth.Guardian` verifies, and deletes the
    # session rows in the same transaction.
    case Gamend.Accounts.get_user(id) do
      %Gamend.Accounts.User{} = user ->
        _ = Gamend.Accounts.revoke_all_tokens(user)
        reply_ok(conn)

      _ ->
        _ =
          Repo.delete_all(
            from(t in UserToken, where: t.user_id == ^id and t.context == ^TokenContext.session())
          )

        reply_ok(conn)
    end
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
