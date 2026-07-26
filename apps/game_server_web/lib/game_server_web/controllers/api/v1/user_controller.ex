defmodule GameServerWeb.Api.V1.UserController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  tags(["Users"])

  operation(:index,
    operation_id: "search_users",
    summary: "Search users by id, username, or display_name",
    parameters: [
      q: [in: :query, schema: %Schema{type: :string}],
      page: [in: :query, schema: %Schema{type: :integer}],
      page_size: [in: :query, schema: %Schema{type: :integer}]
    ],
    responses: [
      ok:
        {"Users (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   username: %Schema{type: :string},
                   display_name: %Schema{type: :string},
                   profile_url: %Schema{type: :string},
                   metadata: %Schema{
                     type: :object,
                     description: "User metadata (accessories, hat, color, etc.)"
                   },
                   lobby_id: %Schema{
                     type: :string,
                     format: :uuid,
                     nullable: false,
                     description:
                       "Lobby ID when user is currently in a lobby. -1 means not currently in a lobby."
                   },
                   party_id: %Schema{
                     type: :string,
                     format: :uuid,
                     nullable: false,
                     description:
                       "Party ID when user is currently in a party. -1 means not currently in a party."
                   },
                   is_online: %Schema{type: :boolean},
                   last_seen_at: %Schema{type: :string, format: :date_time, nullable: false}
                 }
               }
             },
             meta: %Schema{
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
           }
         }}
    ]
  )

  operation(:show,
    operation_id: "get_user",
    summary: "Get a user by id",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok:
        {"User", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             username: %Schema{type: :string},
             display_name: %Schema{type: :string},
             profile_url: %Schema{type: :string},
             metadata: %Schema{
               type: :object,
               description: "User metadata (accessories, hat, color, etc.)"
             },
             lobby_id: %Schema{
               type: :string,
               format: :uuid,
               nullable: false,
               description:
                 "Lobby ID when user is currently in a lobby. -1 means not currently in a lobby."
             },
             party_id: %Schema{
               type: :string,
               format: :uuid,
               nullable: false,
               description:
                 "Party ID when user is currently in a party. -1 means not currently in a party."
             },
             is_online: %Schema{type: :boolean},
             last_seen_at: %Schema{type: :string, format: :date_time, nullable: false}
           }
         }},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    q = Map.get(params, "q", "")
    {page, page_size} = Pagination.params(params)

    users = if q == "", do: [], else: Accounts.search_users(q, page: page, page_size: page_size)
    serialized = Enum.map(users, &serialize_user/1)

    total_count = if q == "", do: 0, else: Accounts.count_search_users(q)

    json(conn, Pagination.envelope(serialized, page, page_size, total_count))
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

      user_id ->
        case Accounts.get_user(user_id) do
          %{} = user -> json(conn, serialize_user(user))
          nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end
    end
  end

  defp serialize_user(user) do
    User.serialize_brief(user)
    |> Map.merge(%{
      lobby_id: user.lobby_id || "",
      party_id: user.party_id || ""
    })
  end
end
