defmodule GameServerWeb.Api.V1.PartyController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServer.Parties
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Parties"])

  @party_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Party ID"},
      leader_id: %Schema{type: :string, format: :uuid, description: "User ID of the party leader"},
      leader_name: %Schema{type: :string, description: "Display name of the party leader"},
      max_size: %Schema{type: :integer, description: "Maximum party members allowed"},
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      members: %Schema{
        type: :array,
        description: "Current party members",
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
            is_online: %Schema{type: :boolean},
            last_seen_at: %Schema{type: :string, format: "date-time"}
          }
        }
      }
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      leader_id: "0198c0de-0002-7000-8000-000000000002",
      leader_name: "Player1",
      max_size: 4,
      metadata: %{},
      members: [
        %{
          id: "0198c0de-0002-7000-8000-000000000002",
          username: "player1-0001",
          display_name: "Player1",
          profile_url: "",
          metadata: %{hat: "red", color: "#FF0000"},
          is_online: true,
          last_seen_at: "2025-01-15T10:30:00Z"
        }
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # OpenApiSpex operation definitions
  # ---------------------------------------------------------------------------

  operation(:show,
    operation_id: "show_party",
    summary: "Get current party",
    description: "Get the party the authenticated user is currently in, including members.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Party details", "application/json", @party_schema},
      not_found:
        {"Not in a party", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      created: {"Party created", "application/json", @party_schema},
      conflict:
        {"Already in a party", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:leave,
    operation_id: "leave_party",
    summary: "Leave the current party",
    description:
      "Leave the party you are currently in. If you are the leader, the party is disbanded and all members are removed.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", %Schema{type: :object}},
      bad_request:
        {"Not in a party", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"Invite sent", "application/json", %Schema{type: :object}},
      forbidden:
        {"Not the leader or target not connected", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      conflict:
        {"Target already in a party or already invited", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"Invite cancelled", "application/json", %Schema{type: :object}},
      forbidden:
        {"Not the leader", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"Joined party", "application/json", @party_schema},
      not_found:
        {"No invite found or party not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      conflict:
        {"Already in a party", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      forbidden:
        {"Party full", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"Invite declined", "application/json", %Schema{type: :object}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:list_invitations,
    operation_id: "list_party_invitations",
    summary: "List pending party invites for the current user",
    description: "Returns all pending PartyInvite records addressed to the authenticated user.",
    security: [%{"authorization" => []}],
    responses: [
      ok:
        {"List of invitations", "application/json",
         %Schema{
           type: :array,
           items: %Schema{
             type: :object,
             properties: %{
               id: %Schema{type: :string, format: :uuid, description: "Invite ID"},
               party_id: %Schema{type: :string, format: :uuid},
               sender_id: %Schema{type: :string, format: :uuid},
               sender_name: %Schema{type: :string},
               recipient_id: %Schema{type: :string, format: :uuid},
               recipient_name: %Schema{type: :string},
               status: %Schema{
                 type: :string,
                 description: "pending | accepted | declined | cancelled"
               },
               inserted_at: %Schema{type: :string, format: "date-time"}
             }
           }
         }},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:list_sent_invitations,
    operation_id: "list_sent_party_invitations",
    summary: "List pending party invites sent by the current leader",
    description:
      "Returns all pending PartyInvite records the authenticated leader has sent that have not yet been accepted or declined.",
    security: [%{"authorization" => []}],
    responses: [
      ok:
        {"List of sent invitations", "application/json",
         %Schema{
           type: :array,
           items: %Schema{
             type: :object,
             properties: %{
               id: %Schema{type: :string, format: :uuid, description: "Invite ID"},
               party_id: %Schema{type: :string, format: :uuid},
               sender_id: %Schema{type: :string, format: :uuid},
               sender_name: %Schema{type: :string},
               recipient_id: %Schema{type: :string, format: :uuid},
               recipient_name: %Schema{type: :string},
               status: %Schema{
                 type: :string,
                 description: "pending | accepted | declined | cancelled"
               },
               inserted_at: %Schema{type: :string, format: "date-time"}
             }
           }
         }},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"User kicked", "application/json", %Schema{type: :object}},
      forbidden:
        {"Not the leader", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"Party updated", "application/json", @party_schema},
      forbidden:
        {"Not the leader", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      created:
        {"Lobby created with all party members", "application/json", %Schema{type: :object}},
      forbidden:
        {"Not the leader or lobby too small", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
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
      ok: {"Lobby joined with all party members", "application/json", %Schema{type: :object}},
      forbidden:
        {"Cannot join (not enough space, locked, wrong password, etc)", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def show(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        if is_nil(user.party_id) do
          conn |> put_status(:not_found) |> json(%{error: "not_in_party"})
        else
          party = Parties.get_party(user.party_id)

          if is_nil(party) do
            conn |> put_status(:not_found) |> json(%{error: "party_not_found"})
          else
            json(conn, serialize_party(party))
          end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def create(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.create_party(user, params) do
          {:ok, party} ->
            conn
            |> put_status(:created)
            |> json(serialize_party(party))

          {:error, :already_in_party} ->
            conn |> put_status(:conflict) |> json(%{error: "already_in_party"})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            })

          _other ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def leave(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.leave_party(user) do
          {:ok, _} ->
            json(conn, %{})

          {:error, :not_in_party} ->
            json(conn, %{})

          _other ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def invite(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(target_user_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          target_id ->
            case Parties.invite_to_party(user, target_id) do
              {:ok, _invite} ->
                json(conn, %{})

              {:error, :not_in_party} ->
                conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})

              {:error, :not_leader} ->
                conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

              {:error, :user_not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "user_not_found"})

              {:error, :already_in_party} ->
                conn |> put_status(:conflict) |> json(%{error: "already_in_party"})

              {:error, :not_connected} ->
                conn |> put_status(:forbidden) |> json(%{error: "not_connected"})

              _other ->
                conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def cancel_party_invite(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(target_user_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          target_id ->
            case Parties.cancel_party_invite(user, target_id) do
              :ok ->
                json(conn, %{})

              {:error, :not_in_party} ->
                conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})

              {:error, :not_leader} ->
                conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

              _other ->
                conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def accept_party_invite(conn, %{"party_id" => party_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(party_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          pid ->
            case Parties.accept_party_invite(user, pid) do
              {:ok, party} ->
                json(conn, serialize_party(party))

              {:error, :no_invite} ->
                conn |> put_status(:not_found) |> json(%{error: "no_invite"})

              {:error, :party_not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "party_not_found"})

              {:error, :already_in_party} ->
                conn |> put_status(:conflict) |> json(%{error: "already_in_party"})

              {:error, :party_full} ->
                conn |> put_status(:forbidden) |> json(%{error: "party_full"})

              _other ->
                conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def decline_party_invite(conn, %{"party_id" => party_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(party_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          pid ->
            Parties.decline_party_invite(user, pid)
            json(conn, %{})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def list_invitations(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        invitations = Parties.list_party_invitations(user)
        json(conn, invitations)

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def list_sent_invitations(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        invitations = Parties.list_sent_party_invitations(user)
        json(conn, invitations)

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def kick(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case parse_id(target_user_id) do
          nil ->
            conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

          target_id ->
            case Parties.kick_member(user, target_id) do
              {:ok, _} ->
                json(conn, %{})

              {:error, :not_in_party} ->
                conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})

              {:error, :not_leader} ->
                conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

              {:error, :cannot_kick_self} ->
                conn |> put_status(:forbidden) |> json(%{error: "cannot_kick_self"})

              {:error, :user_not_found} ->
                conn |> put_status(:not_found) |> json(%{error: "user_not_found"})

              _other ->
                conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
            end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def update(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.update_party(user, params) do
          {:ok, party} ->
            json(conn, serialize_party(party))

          {:error, :not_in_party} ->
            conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})

          {:error, :not_leader} ->
            conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

          {:error, :too_small} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "too_small"})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            })

          _other ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def create_lobby(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case Parties.create_lobby_with_party(user, params) do
          {:ok, lobby} ->
            conn
            |> put_status(:created)
            |> json(serialize_lobby(lobby))

          {:error, :not_in_party} ->
            conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})

          {:error, :not_leader} ->
            conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

          {:error, :lobby_too_small_for_party} ->
            conn |> put_status(:forbidden) |> json(%{error: "lobby_too_small_for_party"})

          {:error, :member_in_lobby} ->
            conn |> put_status(:conflict) |> json(%{error: "member_in_lobby"})

          {:error, :members_offline} ->
            conn |> put_status(:conflict) |> json(%{error: "members_offline"})

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            })

          _other ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
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
                json(conn, serialize_lobby(lobby))

              {:error, :not_in_party} ->
                conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})

              {:error, :not_leader} ->
                conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

              {:error, :member_in_lobby} ->
                conn |> put_status(:conflict) |> json(%{error: "member_in_lobby"})

              {:error, :members_offline} ->
                conn |> put_status(:conflict) |> json(%{error: "members_offline"})

              {:error, :invalid_lobby} ->
                conn |> put_status(:not_found) |> json(%{error: "not_found"})

              {:error, :locked} ->
                conn |> put_status(:forbidden) |> json(%{error: "locked"})

              {:error, :not_enough_space} ->
                conn |> put_status(:forbidden) |> json(%{error: "not_enough_space"})

              {:error, :password_required} ->
                conn |> put_status(:forbidden) |> json(%{error: "password_required"})

              {:error, :invalid_password} ->
                conn |> put_status(:forbidden) |> json(%{error: "invalid_password"})

              _other ->
                conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
            end

          _ ->
            conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
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
