defmodule GamendWeb.Api.V1.UserController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{PlayerStatsResponse, PublicUserPage, PublicUserResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

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
      ok: {"Users (paginated)", "application/json", PublicUserPage}
    ]
  )

  operation(:show,
    operation_id: "get_user",
    summary: "Get a user by id",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok: {"User", "application/json", PublicUserResponse},
      bad_request: Schemas.error("Malformed id"),
      not_found: Schemas.error("Not found")
    ]
  )

  operation(:stats,
    operation_id: "user_stats",
    summary: "Player counts",
    description:
      "Aggregate player counts. Public, and cached — treat the numbers as up to a minute old.",
    responses: [
      ok: {"Player stats", "application/json", PlayerStatsResponse}
    ]
  )

  def stats(conn, _params), do: reply_data(conn, Accounts.player_stats())

  def index(conn, params) do
    q = Map.get(params, "q", "")
    {page, page_size} = Pagination.params(params)

    users = if q == "", do: [], else: Accounts.search_users(q, page: page, page_size: page_size)
    serialized = Enum.map(users, &serialize_user/1)

    total_count = if q == "", do: 0, else: Accounts.count_search_users(q)

    reply_page(conn, serialized, page, page_size, total_count)
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        reply_error(conn, :bad_request, "invalid_id")

      user_id ->
        case Accounts.get_user(user_id) do
          %{} = user -> reply_data(conn, serialize_user(user))
          nil -> reply_error(conn, :not_found, "not_found")
        end
    end
  end

  # `serialize_brief/1` is built for party, lobby and friend member lists, where
  # the caller is already in the room with the user. These two endpoints are
  # public and unauthenticated, so handing back the same payload gives a
  # name-prefix search the whole game-defined metadata map. For a game that
  # keeps position, destination or study state in there, that is a stranger
  # tracking a named player with no account.
  #
  # Metadata is therefore default-deny here, and a host opts individual
  # sections back in through :public_user_metadata_keys.
  # `profile_url` goes with the metadata, for the same reason and one of its
  # own: it is set from an upload *or* imported verbatim from a Google, Discord,
  # Steam or Facebook profile, which means it is frequently a photograph of the
  # account holder. Handing that out from an unauthenticated endpoint, keyed to
  # a name prefix, is the picture and the name together.
  #
  # No lobby or party id either. A lobby id is enough to join a lobby or walk
  # into a WebRTC signaling room, so "which room is this player in" next to a
  # name search was the discovery half of several other problems. The fields
  # went out blank for a while, carrying nothing; now they are gone.
  # Authenticated callers get membership from the lobby, party and channel
  # APIs, which check the caller's relationship to it.
  #
  # Presence too goes out blank, as in `GET /groups/:id/members` to a stranger:
  # whether a named player is online, and when they last were, is for the people
  # who play with them. Friends and members hear it on their channels.
  defp serialize_user(user) do
    user
    |> Serializers.public_brief()
    |> Map.drop([:profile_url])
    |> Map.merge(%{is_online: false, last_seen_at: ~U[1970-01-01 00:00:00Z]})
  end
end
