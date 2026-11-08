defmodule GamendWeb.Api.V1.ChatMuteController do
  @moduledoc """
  Scoped chat mutes, applied by a room's own authority.

  Authority follows the room and mirrors kick: the **lobby host** mutes in their
  lobby, a **group admin** in their group, the **party leader** in their party.
  Like kick, lobby and party actions take no id — the room comes from the
  caller's `lobby_id` / `party_id`.

  Global mutes are deliberately absent here: they are server-authoritative and
  live on the admin API (`/api/v1/admin/bans`, kind `chat`) or a plugin calling
  `Gamend.Chat.mute_user/4`. A mute is a chat ban (`Gamend.Bans`); one placed
  here is recorded with `source: :room`.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.ControllerScope

  alias Gamend.Chat
  alias Gamend.Groups
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{ChatMuteRecordPage, ChatMuteRecordResponse, DeletedCountResponse}
  alias OpenApiSpex.Schema

  require Gamend.Chat.ChatType, as: ChatType

  tags(["Chat"])

  @mute_request %Schema{
    type: :object,
    required: [:target_user_id],
    properties: %{
      target_user_id: %Schema{type: :string, format: :uuid, description: "Player to mute"},
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When the mute lifts. Omit for a permanent mute."
      },
      reason: %Schema{type: :string, description: "Shown to moderators, not to the player"}
    }
  }

  @unmute_request %Schema{
    type: :object,
    required: [:target_user_id],
    properties: %{
      target_user_id: %Schema{type: :string, format: :uuid, description: "Player to unmute"}
    }
  }

  # ── Lobby ──────────────────────────────────────────────────────────────────

  operation(:mute_lobby,
    operation_id: "mute_lobby_member",
    summary: "Mute a player in your lobby",
    description:
      "Silences the player in this lobby's chat. Lobby host only; a hostless " <>
        "lobby has no in-game moderator.",
    security: [%{"authorization" => []}],
    request_body: {"Mute", "application/json", @mute_request},
    responses: [
      ok: {"Muted", "application/json", ChatMuteRecordResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not in a lobby (not_in_lobby)"),
      forbidden: Schemas.error("Not the lobby host")
    ]
  )

  def mute_lobby(conn, params) do
    with_lobby(conn, fn user, lobby ->
      if Lobbies.can_manage_lobby?(user, lobby) do
        do_mute(conn, params, ChatType.lobby(), lobby.id, user)
      else
        reply_error(conn, :forbidden, "not_host")
      end
    end)
  end

  operation(:unmute_lobby,
    operation_id: "unmute_lobby_member",
    summary: "Lift a mute in your lobby",
    security: [%{"authorization" => []}],
    request_body: {"Unmute", "application/json", @unmute_request},
    responses: [
      ok: {"Unmuted", "application/json", DeletedCountResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not in a lobby (not_in_lobby)"),
      forbidden: Schemas.error("Not the lobby host")
    ]
  )

  def unmute_lobby(conn, params) do
    with_lobby(conn, fn user, lobby ->
      if Lobbies.can_manage_lobby?(user, lobby) do
        do_unmute(conn, params, ChatType.lobby(), lobby.id, user)
      else
        reply_error(conn, :forbidden, "not_host")
      end
    end)
  end

  operation(:list_lobby_mutes,
    operation_id: "list_lobby_mutes",
    summary: "List active mutes in your lobby",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, description: "Page number"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, default: 25},
        description: "Items per page (max 100)"
      ]
    ],
    responses: [
      ok: {"Mutes", "application/json", ChatMuteRecordPage},
      not_found: Schemas.error("Not in a lobby (not_in_lobby)"),
      forbidden: Schemas.error("Not the lobby host")
    ]
  )

  def list_lobby_mutes(conn, params) do
    with_lobby(conn, fn user, lobby ->
      if Lobbies.can_manage_lobby?(user, lobby) do
        list_scoped(conn, params, ChatType.lobby(), lobby.id)
      else
        reply_error(conn, :forbidden, "not_host")
      end
    end)
  end

  # ── Group ──────────────────────────────────────────────────────────────────

  operation(:mute_group,
    operation_id: "mute_group_member",
    summary: "Mute a player in a group",
    description: "Silences the player in this group's chat. Group admins only.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID"
      ]
    ],
    request_body: {"Mute", "application/json", @mute_request},
    responses: [
      ok: {"Muted", "application/json", ChatMuteRecordResponse},
      bad_request: Schemas.error("Invalid id"),
      forbidden: Schemas.error("Not a group admin")
    ]
  )

  def mute_group(conn, %{"id" => group_id} = params) do
    with_group_admin(conn, group_id, fn user, group_id ->
      do_mute(conn, params, ChatType.group(), group_id, user)
    end)
  end

  operation(:unmute_group,
    operation_id: "unmute_group_member",
    summary: "Lift a mute in a group",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID"
      ]
    ],
    request_body: {"Unmute", "application/json", @unmute_request},
    responses: [
      ok: {"Unmuted", "application/json", DeletedCountResponse},
      bad_request: Schemas.error("Invalid id"),
      forbidden: Schemas.error("Not a group admin")
    ]
  )

  def unmute_group(conn, %{"id" => group_id} = params) do
    with_group_admin(conn, group_id, fn user, group_id ->
      do_unmute(conn, params, ChatType.group(), group_id, user)
    end)
  end

  operation(:list_group_mutes,
    operation_id: "list_group_mutes",
    summary: "List active mutes in a group",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid},
        description: "Group ID"
      ],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, description: "Page number"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, default: 25},
        description: "Items per page (max 100)"
      ]
    ],
    responses: [
      ok: {"Mutes", "application/json", ChatMuteRecordPage},
      forbidden: Schemas.error("Not a group admin")
    ]
  )

  def list_group_mutes(conn, %{"id" => group_id} = params) do
    with_group_admin(conn, group_id, fn _user, group_id ->
      list_scoped(conn, params, ChatType.group(), group_id)
    end)
  end

  # ── Party ──────────────────────────────────────────────────────────────────

  operation(:mute_party,
    operation_id: "mute_party_member",
    summary: "Mute a player in your party",
    description: "Silences the player in this party's chat. Party leader only.",
    security: [%{"authorization" => []}],
    request_body: {"Mute", "application/json", @mute_request},
    responses: [
      ok: {"Muted", "application/json", ChatMuteRecordResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not in a party (not_in_party)"),
      forbidden: Schemas.error("Not the party leader")
    ]
  )

  def mute_party(conn, params) do
    with_party(conn, fn user, party ->
      if Parties.can_manage_party?(user, party) do
        do_mute(conn, params, ChatType.party(), party.id, user)
      else
        reply_error(conn, :forbidden, "not_leader")
      end
    end)
  end

  operation(:unmute_party,
    operation_id: "unmute_party_member",
    summary: "Lift a mute in your party",
    security: [%{"authorization" => []}],
    request_body: {"Unmute", "application/json", @unmute_request},
    responses: [
      ok: {"Unmuted", "application/json", DeletedCountResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not in a party (not_in_party)"),
      forbidden: Schemas.error("Not the party leader")
    ]
  )

  def unmute_party(conn, params) do
    with_party(conn, fn user, party ->
      if Parties.can_manage_party?(user, party) do
        do_unmute(conn, params, ChatType.party(), party.id, user)
      else
        reply_error(conn, :forbidden, "not_leader")
      end
    end)
  end

  operation(:list_party_mutes,
    operation_id: "list_party_mutes",
    summary: "List active mutes in your party",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, description: "Page number"],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, default: 25},
        description: "Items per page (max 100)"
      ]
    ],
    responses: [
      ok: {"Mutes", "application/json", ChatMuteRecordPage},
      not_found: Schemas.error("Not in a party (not_in_party)"),
      forbidden: Schemas.error("Not the party leader")
    ]
  )

  def list_party_mutes(conn, params) do
    with_party(conn, fn user, party ->
      if Parties.can_manage_party?(user, party) do
        list_scoped(conn, params, ChatType.party(), party.id)
      else
        reply_error(conn, :forbidden, "not_leader")
      end
    end)
  end

  # ── Shared ─────────────────────────────────────────────────────────────────

  defp do_mute(conn, params, scope, scope_ref_id, actor) do
    case target_id(params) do
      nil ->
        reply_error(conn, :bad_request, "invalid_target_user_id")

      target_user_id ->
        attrs = %{
          "expires_at" => param(params, "expires_at"),
          "reason" => param(params, "reason"),
          "muted_by" => actor.id,
          "source" => :room
        }

        case Chat.mute_user(target_user_id, scope, scope_ref_id, attrs) do
          {:ok, mute} ->
            reply_data(conn, serialize(mute))

          {:error, %Ecto.Changeset{} = changeset} ->
            unprocessable(conn, changeset)
        end
    end
  end

  defp do_unmute(conn, params, scope, scope_ref_id, actor) do
    case target_id(params) do
      nil ->
        reply_error(conn, :bad_request, "invalid_target_user_id")

      target_user_id ->
        {:ok, count} = Chat.unmute_user(target_user_id, scope, scope_ref_id, actor.id)
        reply_data(conn, %{deleted: count})
    end
  end

  defp list_scoped(conn, params, scope, scope_ref_id) do
    {page, page_size} = GamendWeb.Pagination.params(params)
    filters = %{"scope" => scope, "scope_ref_id" => scope_ref_id, "active" => true}

    mutes = Chat.list_mutes(filters, page: page, page_size: page_size)
    total_count = Chat.count_mutes(filters)

    reply_page(conn, Enum.map(mutes, &serialize/1), page, page_size, total_count)
  end

  defp serialize(mute) do
    %{
      id: mute.id,
      user_id: mute.user_id,
      scope: mute.scope,
      scope_ref_id: mute.scope_ref_id,
      expires_at: mute.expires_at,
      reason: mute.reason || "",
      muted_by: mute.banned_by || "",
      inserted_at: mute.inserted_at
    }
  end

  defp target_id(params) do
    params
    |> param("target_user_id")
    |> Gamend.UUIDv7.cast_or_nil()
  end

  defp param(params, key) do
    Map.get(params, key) || Map.get(params, String.to_atom(key))
  end

  defp with_group_admin(conn, group_id, fun) do
    with_user(conn, fn user ->
      case Gamend.UUIDv7.cast_or_nil(group_id) do
        nil ->
          reply_error(conn, :bad_request, "invalid_id")

        group_id ->
          if Groups.can_manage_group?(user.id, group_id) do
            fun.(user, group_id)
          else
            reply_error(conn, :forbidden, "not_group_admin")
          end
      end
    end)
  end
end
