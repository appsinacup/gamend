defmodule GamendWeb.Api.V1.PartyController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Parties
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    LobbyResponse,
    OkResponse,
    PartyInvitePage,
    PartyResponse,
    PartyStatsResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Parties"])

  operation(:show,
    operation_id: "show_party",
    summary: "Get current party",
    description: "Get the party the authenticated user is currently in, including members.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Party details", "application/json", PartyResponse},
      not_found: Schemas.error("Not in a party"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:create,
    operation_id: "create_party",
    summary: "Create a party",
    description:
      "Create a new party. The authenticated user becomes the leader and first member. Cannot create a party while already in a party.",
    security: [%{"authorization" => []}],
    request_body: {
      "Party creation parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          max_size: %Schema{
            type: :integer,
            description: "Maximum members allowed (default: 4, min: 2, max: 32)",
            default: 4
          },
          metadata: %Schema{type: :object, description: "Arbitrary metadata"}
        },
        example: %{max_size: 4}
      }
    },
    responses: [
      created: {"Party created", "application/json", PartyResponse},
      conflict: Schemas.error("Already in a party"),
      forbidden: Schemas.error("A game hook refused it (rejected)"),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity: Schemas.error("Validation failed (validation_failed)")
    ]
  )

  operation(:leave,
    operation_id: "leave_party",
    summary: "Leave the current party",
    description:
      "Leave the party you are currently in. A leader hands it to the next member; the last member out disbands it.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:disband,
    operation_id: "disband_party",
    summary: "Disband the current party (leader only)",
    description:
      "End the party for everyone. Distinct from leaving: a leader who LEAVES hands the party " <>
        "to the next member, so ending it outright is its own act and only the leader may do it.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      not_found: Schemas.error("Not in a party (not_in_party)"),
      forbidden: Schemas.error("Not the party leader"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:invite,
    operation_id: "invite_to_party",
    summary: "Invite a user to the party (leader only)",
    description:
      "The party leader invites a user by ID. The target must be a friend of the leader " <>
        "or share at least one group with the leader. A PartyInvite record is created " <>
        "and an informational notification is sent. The invite is independent of notifications.",
    security: [%{"authorization" => []}],
    request_body: {
      "Invite parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          target_user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the user to invite"
          }
        },
        required: [:target_user_id],
        example: %{target_user_id: "0198c0de-0002-7000-8000-000000000002"}
      }
    },
    responses: [
      ok: {"Invite sent", "application/json", OkResponse},
      bad_request: Schemas.error("Malformed id (invalid_id)"),
      forbidden:
        Schemas.error(
          "Not the leader (not_leader), the target is not connected (not_connected), " <>
            "a block stands between the target and a member (blocked), or the target " <>
            "holds too many pending invites (too_many_pending_invites)"
        ),
      not_found: Schemas.error("Not in a party (not_in_party), or no such user (user_not_found)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:cancel_party_invite,
    operation_id: "cancel_party_invite",
    summary: "Cancel a pending party invite (leader only)",
    description: "Cancel an outstanding invite sent to a user. Only the leader can cancel.",
    security: [%{"authorization" => []}],
    request_body: {
      "Cancel parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          target_user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the invited user"
          }
        },
        required: [:target_user_id],
        example: %{target_user_id: "0198c0de-0002-7000-8000-000000000002"}
      }
    },
    responses: [
      ok: {"Invite cancelled", "application/json", OkResponse},
      bad_request: Schemas.error("Malformed id (invalid_id)"),
      forbidden: Schemas.error("Not the leader"),
      not_found: Schemas.error("Not in a party (not_in_party)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:accept_party_invite,
    operation_id: "accept_party_invite",
    summary: "Accept a party invite",
    description:
      "Accept a pending party invite. The user joins the party if there is space. " <>
        "The PartyInvite record is marked as accepted.",
    security: [%{"authorization" => []}],
    request_body: {
      "Accept parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          party_id: %Schema{type: :string, format: :uuid, description: "ID of the party to join"}
        },
        required: [:party_id],
        example: %{party_id: 7}
      }
    },
    responses: [
      ok: {"Joined party", "application/json", PartyResponse},
      not_found: Schemas.error("No invite found or party not found"),
      conflict: Schemas.error("Already in a party"),
      forbidden:
        Schemas.error(
          "Party full (party_full), a block stands between the player and a member " <>
            "(blocked), or a game hook refused it (rejected)"
        ),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:decline_party_invite,
    operation_id: "decline_party_invite",
    summary: "Decline a party invite",
    description: "Decline a pending party invite. The PartyInvite record is marked as declined.",
    security: [%{"authorization" => []}],
    request_body: {
      "Decline parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          party_id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the party to decline"
          }
        },
        required: [:party_id],
        example: %{party_id: 7}
      }
    },
    responses: [
      ok: {"Invite declined", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:list_invitations,
    operation_id: "list_party_invitations",
    summary: "List pending party invites for the current user",
    description: "Returns all pending PartyInvite records addressed to the authenticated user.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number (1-based)"],
      page_size: [in: :query, schema: %Schema{type: :integer}, description: "Rows per page"]
    ],
    responses: [
      ok: {"List of invitations", "application/json", PartyInvitePage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:list_sent_invitations,
    operation_id: "list_sent_party_invitations",
    summary: "List pending party invites sent by the current leader",
    description:
      "Returns all pending PartyInvite records the authenticated leader has sent that have not yet been accepted or declined.",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, description: "Page number (1-based)"],
      page_size: [in: :query, schema: %Schema{type: :integer}, description: "Rows per page"]
    ],
    responses: [
      ok: {"List of sent invitations", "application/json", PartyInvitePage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:kick,
    operation_id: "kick_party_member",
    summary: "Kick a member from the party (leader only)",
    description: "Remove a member from the party. Only the party leader can kick members.",
    security: [%{"authorization" => []}],
    request_body: {
      "Kick parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          target_user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the user to kick"
          }
        },
        required: [:target_user_id],
        example: %{target_user_id: "0198c0de-0002-7000-8000-000000000002"}
      }
    },
    responses: [
      ok: {"User kicked", "application/json", OkResponse},
      bad_request: Schemas.error("Malformed id (invalid_id)"),
      forbidden:
        Schemas.error(
          "Not the leader (not_leader), the leader themselves (cannot_kick_self), " <>
            "or a game hook refused it (rejected)"
        ),
      not_found:
        Schemas.error(
          "Not in a party, or the target is not in it (not_in_party), or no such user " <>
            "(user_not_found)"
        ),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:update,
    operation_id: "update_party",
    summary: "Update party settings (leader only)",
    description:
      "Update party settings such as max_size and metadata. Only the leader can update.",
    security: [%{"authorization" => []}],
    request_body: {
      "Party update parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          max_size: %Schema{type: :integer, description: "New maximum size"},
          metadata: %Schema{type: :object, description: "New metadata"}
        },
        example: %{max_size: 6}
      }
    },
    responses: [
      ok: {"Party updated", "application/json", PartyResponse},
      forbidden: Schemas.error("Not the leader, or a game hook refused it (rejected)"),
      not_found: Schemas.error("Not in a party (not_in_party)"),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity:
        Schemas.error("Smaller than its members (too_small), or validation failed")
    ]
  )

  operation(:create_lobby,
    operation_id: "party_create_lobby",
    summary: "Create a lobby with the party (leader only)",
    description:
      "The party leader creates a new lobby and all party members join it atomically. The party is kept intact. No party member may already be in a lobby. The lobby must have enough capacity for all party members.",
    security: [%{"authorization" => []}],
    request_body: {
      "Lobby creation parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string, description: "Display title for the lobby"},
          max_users: %Schema{type: :integer, description: "Maximum users allowed (default: 8)"},
          is_hidden: %Schema{type: :boolean, description: "Hide from public listings"},
          is_locked: %Schema{type: :boolean, description: "Lock the lobby"},
          password: %Schema{type: :string, description: "Optional password"},
          metadata: %Schema{type: :object, description: "Arbitrary metadata"}
        },
        example: %{title: "Party Lobby", max_users: 8}
      }
    },
    responses: [
      created: {"Lobby created with all party members", "application/json", LobbyResponse},
      conflict:
        Schemas.error(
          "A member is already in a lobby (member_in_lobby), or the party changed while it was being seated (state_changed)"
        ),
      forbidden:
        Schemas.error(
          "Not the leader, the lobby is too small for the party, a member is offline " <>
            "(members_offline), or a game hook refused it (rejected)"
        ),
      not_found: Schemas.error("Not in a party (not_in_party)"),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity: Schemas.error("Validation failed (validation_failed)")
    ]
  )

  operation(:join_lobby,
    operation_id: "party_join_lobby",
    summary: "Join a lobby with the party (leader only)",
    description:
      "The party leader joins an existing lobby and all party members join atomically. The party is kept intact. No party member may already be in a lobby. The lobby must have enough free space for all party members.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Lobby ID",
        required: true
      ]
    ],
    request_body: {
      "Join parameters (optional)",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          password: %Schema{type: :string, description: "Lobby password if required"}
        },
        example: %{password: "secret123"}
      }
    },
    responses: [
      ok: {"Lobby joined with all party members", "application/json", LobbyResponse},
      conflict:
        Schemas.error(
          "A member is already in a lobby (member_in_lobby), or the party changed while it was being seated (state_changed)"
        ),
      forbidden:
        Schemas.error(
          "Cannot join (not enough space, locked, wrong password, a member offline, " <>
            "a block between a member and someone seated (blocked), etc)"
        ),
      not_found:
        Schemas.error(
          "Not in a party (not_in_party), or no such lobby or a hidden one (not_found)"
        ),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  operation(:stats,
    operation_id: "party_stats",
    summary: "Party counts",
    description:
      "Aggregate party counts. Public, and cached — treat the numbers as up to a minute old.",
    responses: [
      ok: {"Party stats", "application/json", PartyStatsResponse}
    ]
  )

  def stats(conn, _params), do: reply_data(conn, Parties.stats())

  def show(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        if is_nil(user.party_id) do
          reply_error(conn, :not_found, "not_in_party")
        else
          party = Parties.get_party(user.party_id)

          if is_nil(party) do
            reply_error(conn, :not_found, "party_not_found")
          else
            reply_data(conn, serialize_party(party))
          end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def create(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.create_party(user, params) do
          {:ok, party} ->
            reply_data(conn, :created, serialize_party(party))

          # The unique index on `leader_id` is the seat race, which
          # `already_in_party` answers: a changeset is the input's fault.
          {:error, %Ecto.Changeset{} = changeset} ->
            unprocessable(conn, changeset)

          {:error, reason} ->
            reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def leave(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.leave_party(user) do
          {:ok, _} ->
            reply_ok(conn)

          {:error, :not_in_party} ->
            reply_ok(conn)

          {:error, reason} ->
            reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def disband(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{party_id: party_id} = user when is_binary(party_id) ->
        do_disband(conn, user, Parties.get_party(party_id))

      %User{} ->
        reply_error(conn, :not_found, "not_in_party")

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  # `can_manage_party?/2` is the leader test. Comparing leader_id here would be
  # a copy of it that stops following the context the day leadership means
  # anything more than one id.
  defp do_disband(conn, user, %{} = party) do
    if Parties.can_manage_party?(user, party) do
      # The check above is an early refusal: `disband/2` asks again under the
      # party's lock, where a hand-over that landed first is seen.
      case Parties.disband(party, user) do
        {:ok, _} -> reply_ok(conn)
        {:error, :not_leader} -> reply_error(conn, :forbidden, "not_party_leader")
        {:error, reason} -> reply_reason(conn, reason)
      end
    else
      reply_error(conn, :forbidden, "not_party_leader")
    end
  end

  # The signed-in user can be a cached copy, still naming a party since gone.
  defp do_disband(conn, _user, nil),
    do: reply_error(conn, :not_found, "not_in_party")

  def invite(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(target_user_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          target_id ->
            case Parties.invite_to_party(user, target_id) do
              {:ok, _invite} -> reply_ok(conn)
              {:error, reason} -> reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def cancel_party_invite(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(target_user_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          target_id ->
            case Parties.cancel_party_invite(user, target_id) do
              :ok -> reply_ok(conn)
              {:error, reason} -> reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def accept_party_invite(conn, %{"party_id" => party_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(party_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          pid ->
            case Parties.accept_party_invite(user, pid) do
              {:ok, party} -> reply_data(conn, serialize_party(party))
              {:error, reason} -> reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def decline_party_invite(conn, %{"party_id" => party_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(party_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          pid ->
            Parties.decline_party_invite(user, pid)
            reply_ok(conn)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def list_invitations(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        {page, page_size} = GamendWeb.Pagination.params(params)
        rows = Parties.list_party_invitations(user, page: page, page_size: page_size)
        reply_page(conn, rows, page, page_size, Parties.count_party_invitations(user))

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def list_sent_invitations(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        {page, page_size} = GamendWeb.Pagination.params(params)
        rows = Parties.list_sent_party_invitations(user, page: page, page_size: page_size)
        reply_page(conn, rows, page, page_size, Parties.count_sent_party_invitations(user))

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def kick(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(target_user_id) do
          nil ->
            reply_error(conn, :bad_request, "invalid_id")

          target_id ->
            case Parties.kick_member(user, target_id) do
              {:ok, _} ->
                reply_ok(conn)

              # The party was disbanded while the kick was on its way.
              {:error, :not_found} ->
                reply_error(conn, :not_found, "not_in_party")

              {:error, reason} ->
                reply_reason(conn, reason)
            end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def update(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.update_party(user, params) do
          {:ok, party} ->
            reply_data(conn, serialize_party(party))

          {:error, %Ecto.Changeset{} = changeset} ->
            unprocessable(conn, changeset)

          {:error, reason} ->
            reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def create_lobby(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.create_lobby_with_party(user, params) do
          {:ok, lobby} ->
            reply_data(conn, :created, serialize_lobby(lobby))

          # A lobby's title is a display name, never unique: a failed
          # changeset is always the input's fault.
          {:error, %Ecto.Changeset{} = changeset} ->
            unprocessable(conn, changeset)

          {:error, reason} ->
            reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  def join_lobby(conn, %{"id" => id} = params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Ecto.UUID.cast(to_string(id)) do
          {:ok, lobby_id} ->
            opts = %{password: Map.get(params, "password") || Map.get(params, :password)}

            case Parties.join_lobby_with_party(user, lobby_id, opts) do
              {:ok, lobby} ->
                reply_data(conn, serialize_lobby(lobby))

              {:error, :invalid_lobby} ->
                reply_error(conn, :not_found, "not_found")

              {:error, reason} ->
                reply_reason(conn, reason)
            end

          _ ->
            reply_error(conn, :not_found, "not_found")
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_party(party) do
    Serializers.serialize_party(party, include_timestamps: true)
  end

  defp serialize_lobby(lobby) do
    Serializers.serialize_lobby(lobby, include_passworded: true)
  end
end
