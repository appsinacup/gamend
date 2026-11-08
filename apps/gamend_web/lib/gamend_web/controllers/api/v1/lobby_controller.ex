defmodule GamendWeb.Api.V1.LobbyController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.ControllerScope, only: [with_lobby: 2]
  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{LobbyPage, LobbyResponse, LobbyStatsResponse, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  require GamendWeb.UrlParam, as: UrlParam

  @secret123 "secret123"

  tags(["Lobbies"])

  operation(:index,
    operation_id: "list_lobbies",
    summary: "List lobbies",
    description:
      "Return all non-hidden lobbies. Supports optional text search via 'title', metadata filters, password/lock filters, and numeric min/max for max_users.",
    parameters: [
      title: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Search term for title"
      ],
      is_passworded: [
        in: :query,
        schema: %Schema{type: :boolean},
        description: "Filter by passworded lobbies (omit for any)"
      ],
      is_locked: [
        in: :query,
        schema: %Schema{type: :boolean},
        description: "Filter by locked status (omit for any)"
      ],
      min_users: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Minimum max_users to include"
      ],
      max_users: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Maximum max_users to include"
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (max results per page)",
        required: false
      ],
      metadata_key: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Optional metadata key to filter by"
      ],
      metadata_value: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Optional metadata value to match (used with metadata_key)"
      ]
    ],
    responses: [
      ok: {"List of lobbies (paginated)", "application/json", LobbyPage}
    ]
  )

  operation(:create,
    operation_id: "create_lobby",
    summary: "Create a lobby",
    description:
      "Create a new lobby. The authenticated user becomes the host and is automatically joined.",
    security: [%{"authorization" => []}],
    request_body: {
      "Lobby creation parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string, description: "Display title for the lobby"},
          max_users: %Schema{
            type: :integer,
            description: "Maximum users allowed (default: 8)",
            default: 8
          },
          is_hidden: %Schema{
            type: :boolean,
            description: "Hide from public listings",
            default: false
          },
          is_locked: %Schema{type: :boolean, description: "Lock the lobby", default: false},
          password: %Schema{
            type: :string,
            description: "Optional password to protect the lobby"
          },
          metadata: %Schema{type: :object, description: "Arbitrary metadata"},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        },
        example: %{
          title: "My Game Lobby",
          max_users: 4,
          is_hidden: false
        }
      }
    },
    responses: [
      created: {"Lobby created", "application/json", LobbyResponse},
      conflict:
        Schemas.error(
          "Already in a lobby (already_in_lobby), or a party member is (member_in_lobby)"
        ),
      forbidden:
        Schemas.error(
          "In a party without leading it, the party cannot follow, or a game hook refused it (rejected)"
        ),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity: Schemas.error("Validation failed (validation_failed)")
    ]
  )

  operation(:set_state,
    operation_id: "set_lobby_state",
    summary: "Set lobby state (host or pinned WebRTC host)",
    description:
      "Move a lobby to another lifecycle state. Allowed for the host of a " <>
        "host-managed lobby and for the lobby's pinned WebRTC host; a hostless " <>
        "(matchmaking) lobby with no pinned host belongs to the server, so no " <>
        "player may move it. Targets the caller's own lobby unless lobby_id " <>
        "names another - which is how a pinned WebRTC host, seated in no lobby, " <>
        "moves the room it runs. The vocabulary is the game's (core documents " <>
        "created, starting, playing, ended); the game's before_lobby_state_change " <>
        "hook enforces its own words and ordering.",
    security: [%{"authorization" => []}],
    request_body: {
      "Target state",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          state: %Schema{type: :string, description: "Target lifecycle state"},
          lobby_id: %Schema{
            type: :string,
            description: "Lobby to move. Defaults to the caller's own lobby."
          }
        },
        required: [:state]
      }
    },
    responses: %{
      200 => {"Updated lobby", "application/json", LobbyResponse},
      400 => Schemas.error("Missing state / malformed id"),
      401 => Schemas.error("Not authenticated"),
      403 => Schemas.error("No authority over the lobby, or a game hook refused it (rejected)"),
      404 => Schemas.error("Not in a lobby (not_in_lobby), or not found"),
      409 => Schemas.error("Another change moved the lobby's state first (state_changed)"),
      422 => Schemas.error("An empty or overlong state (invalid_state)")
    }
  )

  def set_state(conn, %{"state" => state} = params) when is_binary(state) do
    with_target_lobby(conn, params, fn user, lobby ->
      # A lobby deleted after it was read is `not_found`, as a read after the
      # delete would answer; a game hook's veto is 403 `rejected`.
      case Lobbies.transition_state_by_host(user, lobby, state) do
        {:ok, updated} -> reply_data(conn, serialize_lobby(updated))
        {:error, reason} -> reply_reason(conn, reason)
      end
    end)
  end

  def set_state(conn, _params) do
    reply_error(conn, :bad_request, "state_required")
  end

  operation(:update,
    operation_id: "update_lobby",
    summary: "Update lobby (host or pinned WebRTC host)",
    description:
      "Update a lobby's settings. Allowed for the host of a host-managed lobby and for " <>
        "the lobby's pinned WebRTC host; a hostless (matchmaking) lobby with no pinned " <>
        "host belongs to the server, so no player may edit it (both cases return 403). " <>
        "Targets the caller's own lobby unless lobby_id names another - which is how a " <>
        "pinned WebRTC host, seated in no lobby, edits the room it runs. Admins can still " <>
        "modify any lobby from the admin console or the admin API - those changes are " <>
        "broadcast to viewers.",
    security: [%{"authorization" => []}],
    request_body: {
      "Lobby update parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          lobby_id: %Schema{
            type: :string,
            description: "Lobby to update. Defaults to the caller's own lobby."
          },
          title: %Schema{type: :string, description: "New display title"},
          max_users: %Schema{type: :integer, description: "New maximum users"},
          is_hidden: %Schema{type: :boolean, description: "Hide from public listings"},
          is_locked: %Schema{type: :boolean, description: "Lock the lobby"},
          password: %Schema{type: :string, description: "New password (empty string to clear)"},
          metadata: %Schema{type: :object, description: "New metadata"},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        },
        example: %{
          title: "Updated Lobby Name",
          max_users: 6,
          is_locked: true
        }
      }
    },
    responses: [
      ok: {"Lobby updated", "application/json", LobbyResponse},
      bad_request: Schemas.error("Malformed id"),
      forbidden:
        Schemas.error("No authority over the lobby, or a game hook refused it (rejected)"),
      not_found: Schemas.error("Not in a lobby (not_in_lobby), or not found"),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity: Schemas.error("Smaller than its members, or validation failed")
    ]
  )

  operation(:join,
    operation_id: "join_lobby",
    summary: "Join a lobby",
    description:
      "Join an existing lobby. If the lobby requires a password, include it in the request body.",
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
        example: %{password: @secret123}
      }
    },
    responses: [
      ok: {"Successfully joined", "application/json", LobbyResponse},
      forbidden:
        Schemas.error(
          "Cannot join (locked, full, wrong password, a block with someone seated (blocked), " <>
            "a game hook refused it, etc)"
        ),
      not_found: Schemas.error("Lobby not found, or hidden"),
      conflict: Schemas.error("Already in a lobby, or a party member is"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:leave,
    operation_id: "leave_lobby",
    summary: "Leave the current lobby",
    description: "Leave the lobby you are currently in.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:disband,
    operation_id: "disband_lobby",
    summary: "Disband the current lobby (host only)",
    description:
      "Delete the lobby for everyone. Distinct from leaving: leaving hands the lobby to the next " <>
        "member, so ending it outright is its own act and only the host may do it. A hostless " <>
        "(matchmaking) lobby has no host to authorise it and is refused.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      not_found: Schemas.error("Not in a lobby (not_in_lobby)"),
      forbidden: Schemas.error("Not the lobby host, or a game hook refused (`rejected`)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:kick,
    operation_id: "kick_user",
    summary: "Kick a user from the lobby (host only)",
    description:
      "Remove a user from the lobby. Only the host can kick users via the API (returns 403 if not host).",
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
      forbidden:
        Schemas.error("Not the host, cannot kick this user, or a game hook refused it (rejected)"),
      not_found:
        Schemas.error("The caller is in no lobby (not_in_lobby), or the target is not in it"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  operation(:quick_join,
    operation_id: "quick_join",
    summary: "Quick-join or create a lobby",
    description:
      "Attempt to find an open, non-passworded lobby that matches the provided criteria and join it; if none found, create a new lobby. The authenticated user will become the host when a lobby is created.",
    security: [%{"authorization" => []}],
    request_body: {
      "Quick join parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string, description: "Optional title for a newly created lobby"},
          max_users: %Schema{
            type: :integer,
            description: "Optional maximum users to match/create"
          },
          metadata: %Schema{
            type: :object,
            description: "Optional metadata to match (substring match)"
          }
        }
      }
    },
    responses: [
      ok: {"Lobby joined or created", "application/json", LobbyResponse},
      conflict: Schemas.error("Already in a lobby, or a party member is (member_in_lobby)"),
      forbidden: Schemas.error("Not the party leader, members offline, or rejected"),
      unauthorized: Schemas.error("Not authenticated"),
      unprocessable_entity: Schemas.error("Validation failed (validation_failed)")
    ]
  )

  operation(:stats,
    operation_id: "lobby_stats",
    summary: "Lobby counts",
    description:
      "Aggregate lobby counts, including spectators. Public, and cached — treat the numbers as up to a minute old.",
    responses: [
      ok: {"Lobby stats", "application/json", LobbyStatsResponse}
    ]
  )

  def stats(conn, _params), do: reply_data(conn, Lobbies.stats())

  def index(conn, params) do
    params = params || %{}

    filters =
      %{}
      |> maybe_put_string_filter(:title, param_value(params, UrlParam.title(), :title))
      |> maybe_put_bool_filter(
        :is_passworded,
        param_value(params, "is_passworded", :is_passworded)
      )
      |> maybe_put_bool_filter(:is_locked, param_value(params, UrlParam.is_locked(), :is_locked))
      |> maybe_put_int_filter(:min_users, param_value(params, UrlParam.min_users(), :min_users))
      |> maybe_put_int_filter(:max_users, param_value(params, UrlParam.max_users(), :max_users))
      |> maybe_put_string_filter(
        :metadata_key,
        param_value(params, UrlParam.metadata_key(), :metadata_key)
      )
      |> maybe_put_string_filter(
        :metadata_value,
        param_value(params, UrlParam.metadata_value(), :metadata_value)
      )

    {page, page_size} = GamendWeb.Pagination.params(params)

    lobbies = Lobbies.list_lobbies(filters, page: page, page_size: page_size)
    total_count = Lobbies.count_list_lobbies(filters)

    reply_page(conn, Enum.map(lobbies, &serialize_lobby/1), page, page_size, total_count)
  end

  defp serialize_lobby(lobby) do
    Serializers.serialize_lobby(lobby, include_passworded: true, include_slowdown: true)
  end

  operation(:show,
    operation_id: "get_lobby",
    security: [%{"authorization" => []}],
    summary: "Get a single lobby",
    description:
      "Return a lobby with its current members and spectator count. Requires a signed-in user; a hidden lobby is visible only to its own members, and anyone else gets 404.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Lobby ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Lobby details", "application/json", LobbyResponse},
      bad_request: Schemas.error("Malformed id"),
      not_found: Schemas.error("Not found")
    ]
  )

  def show(conn, %{"id" => id_str}) do
    caller = Scope.user(conn.assigns[:current_scope])

    with {:ok, lobby_id} <- Ecto.UUID.cast(id_str),
         %Gamend.Lobbies.Lobby{} = lobby <- Lobbies.get_lobby(lobby_id),
         true <- Lobbies.can_view_lobby?(caller, lobby) do
      reply_data(
        conn,
        Serializers.serialize_lobby(lobby,
          include_passworded: true,
          include_slowdown: true,
          include_members: true,
          include_spectator_count: true,
          outsider: not match?(%User{lobby_id: ^lobby_id}, caller)
        )
      )
    else
      :error ->
        reply_error(conn, :bad_request, "invalid_id")

      nil ->
        reply_error(conn, :not_found, "not_found")

      # 404 rather than 403 for a hidden lobby the caller is not in: a 403
      # confirms it exists, which is the thing hiding it is meant to conceal.
      false ->
        reply_error(conn, :not_found, "not_found")
    end
  end

  ### API actions (create/join/update/leave/kick) ###

  # `hostless` and `host_id` are server-owned and are dropped, not rejected.
  #
  # The old guard compared against the boolean `true` only, so `"hostless":
  # "true"` sailed past it and Ecto cast the string — producing a lobby with no
  # host, which nobody can manage, and which game hooks reasonably read as
  # "created by the server". Stripping is also the better shape than a 401: a
  # client sending a field it does not own gets its lobby, minus that field.
  @server_owned_lobby_fields ~w(hostless host_id)a ++ ~w(hostless host_id)

  def create(conn, params) do
    params = Map.drop(params, @server_owned_lobby_fields)

    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        user = Gamend.Accounts.get_user(user.id)

        cond do
          # Non-leader party members must leave the party first
          user.party_id != nil and not Parties.can_manage_party?(user, user.party_id) ->
            reply_error(conn, :forbidden, "in_party")

          # Party leader: automatically bring the whole party
          user.party_id != nil and Parties.can_manage_party?(user, user.party_id) ->
            create_lobby_as_party_leader(conn, user, params)

          # Not in a party: normal create flow
          true ->
            create_lobby_solo(conn, user, params)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp create_lobby_as_party_leader(conn, user, params) do
    case Parties.create_lobby_with_party(user, params) do
      {:ok, lobby} ->
        reply_data(conn, :created, serialize_lobby(lobby))

      # A lobby's title is a display name, never unique: a failed changeset is
      # always the input's fault.
      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      # `already_in_lobby` is the leader taking a seat elsewhere between the
      # party's check and the create.
      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  defp create_lobby_solo(conn, user, params) do
    attrs = Map.put(params, "host_id", user.id)

    case Lobbies.create_lobby(attrs) do
      {:ok, lobby} ->
        reply_data(conn, :created, serialize_lobby(lobby))

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  def join(conn, %{"id" => id} = params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        user = Gamend.Accounts.get_user(user.id)
        password = Map.get(params, "password") || Map.get(params, :password)

        case Ecto.UUID.cast(to_string(id)) do
          {:ok, lobby_id} ->
            cond do
              # Non-leader party members cannot join a lobby individually
              user.party_id != nil and not Parties.can_manage_party?(user, user.party_id) ->
                reply_error(conn, :forbidden, "in_party")

              # Party leader: bring the whole party
              user.party_id != nil and Parties.can_manage_party?(user, user.party_id) ->
                join_lobby_as_party_leader(conn, user, lobby_id, params)

              # Not in a party: normal join
              true ->
                join_lobby_solo(conn, user, lobby_id, %{password: password})
            end

          _ ->
            reply_error(conn, :not_found, "not_found")
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp join_lobby_as_party_leader(conn, user, lobby_id, params) do
    password = Map.get(params, "password") || Map.get(params, :password)
    opts = if password, do: %{password: password}, else: %{}

    case Parties.join_lobby_with_party(user, lobby_id, opts) do
      {:ok, lobby} -> reply_data(conn, serialize_lobby(lobby))
      {:error, :invalid_lobby} -> reply_error(conn, :not_found, "not_found")
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  defp join_lobby_solo(conn, user, lobby_id, opts) do
    case Lobbies.join_lobby(user, lobby_id, opts) do
      {:ok, _member} ->
        # Disbanded straight after the join: answered as a join to a lobby gone.
        case Lobbies.get_lobby(lobby_id) do
          %Lobbies.Lobby{} = lobby -> reply_data(conn, serialize_lobby(lobby))
          nil -> reply_error(conn, :not_found, "not_found")
        end

      {:error, :invalid_lobby} ->
        reply_error(conn, :not_found, "not_found")

      # A hidden lobby is `not_found` too: a 403 would confirm it exists.
      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  def quick_join(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        user = Gamend.Accounts.get_user(user.id)

        if user.party_id != nil do
          # Party leader quick-joins with the whole party
          do_party_quick_join(conn, user, params)
        else
          do_quick_join(conn, user, params)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp do_party_quick_join(conn, user, params) do
    case Gamend.Parties.quick_join_with_party(user, params) do
      {:ok, lobby} -> reply_data(conn, serialize_lobby(lobby))
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  defp do_quick_join(conn, user, params) do
    title = Map.get(params, "title") || Map.get(params, :title)
    max_users = Map.get(params, "max_users") || Map.get(params, :max_users)

    # Normalize metadata: allow either a map (from parsed JSON) or a
    # JSON-encoded string. If a client sends the metadata as a string
    # (eg. form submission), try to decode it to a map; otherwise fall
    # back to an empty map.
    metadata_raw = Map.get(params, "metadata") || Map.get(params, :metadata)

    metadata =
      case metadata_raw do
        nil ->
          %{}

        "" ->
          %{}

        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        m when is_map(m) ->
          m

        _ ->
          %{}
      end

    case Lobbies.quick_join(user, title, max_users, metadata) do
      {:ok, lobby} -> reply_data(conn, serialize_lobby(lobby))
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  def update(conn, params) do
    with_target_lobby(conn, params, fn user, lobby ->
      case Lobbies.update_lobby_by_host(user, lobby, Map.drop(params, ["lobby_id", :lobby_id])) do
        {:ok, updated} ->
          reply_data(conn, serialize_lobby(updated))

        {:error, %Ecto.Changeset{} = changeset} ->
          unprocessable(conn, changeset)

        {:error, reason} ->
          reply_reason(conn, reason)
      end
    end)
  end

  # Which lobby the caller means. Normally the one it is sitting in — but a
  # pinned WebRTC host is seated in no lobby (that is the point of pinning one:
  # a headless server runs the room without occupying a slot), so it names the
  # lobby explicitly instead. `can_view_lobby?` gates the named one: a caller
  # with no relationship to a hidden lobby gets the same 404 as `show/2`, since
  # a 403 would confirm it exists. Authority itself is checked downstream, so
  # the answer to "may I?" comes from one place.
  defp with_target_lobby(conn, params, fun) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case target_lobby(user, Map.get(params, "lobby_id") || Map.get(params, :lobby_id)) do
          {:ok, lobby} -> fun.(user, lobby)
          # `not_in_lobby` and `not_found` are 404, `invalid_id` 400.
          {:error, reason} -> reply_reason(conn, reason)
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  defp target_lobby(%User{lobby_id: nil}, nil), do: {:error, :not_in_lobby}
  # The signed-in user can be a cached copy, still naming a lobby since deleted.
  defp target_lobby(%User{lobby_id: lobby_id}, nil) do
    case Lobbies.get_lobby(lobby_id) do
      %Lobbies.Lobby{} = lobby -> {:ok, lobby}
      nil -> {:error, :not_in_lobby}
    end
  end

  defp target_lobby(%User{} = user, raw_id) do
    with {:ok, lobby_id} <- Ecto.UUID.cast(raw_id),
         %Gamend.Lobbies.Lobby{} = lobby <- Lobbies.get_lobby(lobby_id),
         true <- Lobbies.can_view_lobby?(user, lobby) do
      {:ok, lobby}
    else
      :error -> {:error, :invalid_id}
      _ -> {:error, :not_found}
    end
  end

  def kick(conn, %{"target_user_id" => target_user_id}) do
    with_lobby(conn, fn user, lobby ->
      case Gamend.Accounts.get_user(target_user_id) do
        %User{} = target -> do_kick(conn, user, lobby, target)
        nil -> reply_error(conn, :not_found, "not_found")
      end
    end)
  end

  defp do_kick(conn, user, lobby, target) do
    case Lobbies.kick_user(user, lobby, target) do
      {:ok, _} ->
        reply_ok(conn)

      # Gone, or not seated in this lobby: either way not a member to kick.
      {:error, reason} when reason in [:not_found, :not_in_lobby] ->
        reply_error(conn, :not_found, "not_found")

      {:error, reason} ->
        reply_reason(conn, reason)
    end
  end

  def disband(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{lobby_id: lobby_id} = user when is_binary(lobby_id) ->
        do_disband(conn, user, Lobbies.get_lobby(lobby_id))

      %User{} ->
        reply_error(conn, :not_found, "not_in_lobby")

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  # A hostless lobby is server-managed: nobody is its owner, so nobody can end
  # it from the API.
  defp do_disband(conn, _user, %{hostless: true}),
    do: reply_error(conn, :forbidden, "not_host")

  # Who may end a lobby is the context's rule — the same one `kick` and
  # `update` go through. Comparing host_id here was a second copy of it living
  # in the controller.
  defp do_disband(conn, user, %{} = lobby) do
    if Lobbies.can_manage_lobby?(user, lobby) do
      case Lobbies.delete_lobby(lobby) do
        {:ok, _} -> reply_ok(conn)
        # Deleted since it was read: the caller's lobby is gone.
        {:error, :not_found} -> reply_error(conn, :not_found, "not_in_lobby")
        {:error, reason} -> reply_reason(conn, reason)
      end
    else
      reply_error(conn, :forbidden, "not_host")
    end
  end

  # The signed-in user can be a cached copy, still naming a lobby since deleted.
  defp do_disband(conn, _user, nil),
    do: reply_error(conn, :not_found, "not_in_lobby")

  def leave(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        # Use the authenticated user's lobby (ignore path id)
        if is_nil(user.lobby_id) do
          reply_ok(conn)
        else
          case Lobbies.leave_lobby(user) do
            {:ok, _} ->
              reply_ok(conn)

            {:error, :not_in_lobby} ->
              reply_ok(conn)

            {:error, reason} ->
              reply_reason(conn, reason)
          end
        end

      _ ->
        reply_error(conn, :unauthorized, "not_authenticated")
    end
  end
end
