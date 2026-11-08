defmodule GamendWeb.Api.V1.Admin.BanController do
  @moduledoc """
  Admin API for bans (`Gamend.Bans`): IP addresses, accounts and chat mutes,
  the same list `/admin/bans` shows, so a script can do what the console can.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Bans
  alias GamendWeb.Plugs.IpBan
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AdminBanPage, AdminBanResponse}
  alias OpenApiSpex.Schema

  require Gamend.Bans.BanKind, as: BanKind
  require Gamend.Bans.BanScope, as: BanScope
  require GamendWeb.UrlParam, as: UrlParam

  tags(["Admin – Bans"])

  operation(:index,
    operation_id: "admin_list_bans",
    summary: "List bans (admin)",
    description:
      "Every ban, ended ones too, newest first. `active=true` keeps the ones in force.",
    security: [%{"authorization" => []}],
    parameters: [
      kind: [
        in: :query,
        schema: %Schema{type: :string, enum: BanKind.all()}
      ],
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      subject: [
        in: :query,
        schema: %Schema{type: :string},
        description: "The IP (an IPv6 one as its /64) or the user id"
      ],
      scope: [
        in: :query,
        schema: %Schema{
          type: :string,
          enum: BanScope.all()
        },
        description: "A chat ban's reach"
      ],
      scope_ref_id: [
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        description: "A chat ban's room"
      ],
      active: [in: :query, schema: %Schema{type: :boolean}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok: {"Bans", "application/json", AdminBanPage},
      bad_request: Schemas.error("Invalid id")
    ]
  )

  def index(conn, params) do
    if Enum.all?(
         [UrlParam.user_id(), "scope_ref_id"],
         &(params[&1] in [nil, ""] or parse_id(params[&1]))
       ),
       do: list(conn, params),
       else: invalid_id(conn)
  end

  defp list(conn, params) do
    filters =
      %{}
      |> maybe_put_string_filter(UrlParam.kind(), params["kind"])
      |> maybe_put_string_filter(UrlParam.user_id(), params["user_id"])
      |> maybe_put_string_filter("subject", params["subject"])
      |> maybe_put_string_filter("scope", params["scope"])
      |> maybe_put_string_filter("scope_ref_id", params["scope_ref_id"])
      |> maybe_put_bool_filter(UrlParam.active(), params["active"])

    {page, page_size} = GamendWeb.Pagination.params(params)
    bans = Bans.list(filters, page: page, page_size: page_size)

    reply_page(conn, Enum.map(bans, &serialize/1), page, page_size, Bans.count(filters))
  end

  operation(:create,
    operation_id: "admin_create_ban",
    summary: "Ban an IP address, an account or a chat sender (admin)",
    description:
      "An `ip` ban takes `ip` (an IPv6 address is banned as its /64); an `account` " <>
        "ban takes `user_id`, and may not name an admin. A `chat` ban (a mute) takes " <>
        "`user_id` and `scope`: `global` (every chat, friend DMs included) or " <>
        "`lobby`, `group` or `party` with that room's `scope_ref_id`. Banning a " <>
        "target that is already banned replaces its ban. A banned account still " <>
        "signs in and reads `GET /me`; everything else refuses it.",
    security: [%{"authorization" => []}],
    request_body:
      {"Ban", "application/json",
       %Schema{
         type: :object,
         required: [:kind],
         properties: %{
           kind: %Schema{type: :string, enum: BanKind.all()},
           ip: %Schema{type: :string, description: "For an `ip` ban"},
           user_id: %Schema{
             type: :string,
             format: :uuid,
             description: "For an `account` or `chat` ban"
           },
           scope: %Schema{
             type: :string,
             enum: BanScope.all(),
             default: BanScope.global(),
             description: "For a `chat` ban"
           },
           scope_ref_id: %Schema{
             type: :string,
             format: :uuid,
             description: "For a scoped `chat` ban: the lobby, group or party"
           },
           expires_at: %Schema{
             type: :string,
             format: :"date-time",
             nullable: true,
             description: "When the ban ends. Omit for a permanent ban."
           },
           reason: %Schema{type: :string, description: "Shown to a banned player"}
         }
       }},
    responses: [
      ok: {"Banned (replacing any earlier ban)", "application/json", AdminBanResponse},
      bad_request: Schemas.error("Invalid kind, ip, user id or room id"),
      unprocessable_entity: Schemas.error("Invalid ban")
    ]
  )

  def create(conn, params) do
    case expires_at(params["expires_at"]) do
      {:ok, expires_at} -> place(conn, params, expires_at)
      :error -> reply_error(conn, :bad_request, "invalid_expires_at")
    end
  end

  defp place(conn, params, expires_at) do
    opts = [
      expires_at: expires_at,
      reason: Gamend.Parse.blank_to_nil(params["reason"]),
      source: :api,
      by: Scope.user_id(conn.assigns[:current_scope])
    ]

    result =
      case {params["kind"], params["ip"], parse_id(params["user_id"])} do
        {BanKind.ip(), ip, _} when is_binary(ip) and ip != "" ->
          IpBan.ban(ip, opts)

        {BanKind.account(), _, user_id} when is_binary(user_id) ->
          Bans.ban(:account, user_id, opts)

        {BanKind.chat(), _, user_id} when is_binary(user_id) ->
          chat_ban(user_id, params, opts)

        _ ->
          :invalid
      end

    case result do
      {:ok, ban} ->
        reply_data(conn, ban.id |> Bans.get() |> serialize())

      {:error, changeset} ->
        unprocessable(conn, changeset)

      :invalid ->
        reply_error(
          conn,
          :bad_request,
          "invalid_ban",
          "Send kind ip with ip, or kind account or chat with user_id"
        )
    end
  end

  operation(:delete,
    operation_id: "admin_lift_ban",
    summary: "Lift a ban (admin)",
    description:
      "Ends the ban on that ban's target now. The row stays, as history, with " <>
        "`lifted_at` set; lifting a ban that already ended changes nothing.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"The ban, as it is now", "application/json", AdminBanResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not found")
    ]
  )

  def delete(conn, %{"id" => id}) do
    with ban_id when is_binary(ban_id) <- parse_id(id) || :invalid,
         %Bans.Ban{} = ban <- Bans.get(ban_id) do
      # Only this ban: a target banned again since has a newer one, which an
      # old row's id must not lift.
      if Bans.active?(ban) do
        {:ok, _lifted} =
          Bans.lift_ban(ban, by: Scope.user_id(conn.assigns[:current_scope]))
      end

      reply_data(conn, ban.id |> Bans.get() |> serialize())
    else
      :invalid -> invalid_id(conn)
      nil -> reply_error(conn, :not_found, "not_found")
    end
  end

  defp chat_ban(user_id, params, opts) do
    raw = params["scope_ref_id"]
    ref = parse_id(raw)

    if raw in [nil, ""] or ref,
      do:
        Bans.ban(
          :chat,
          user_id,
          [scope: params["scope"] || BanScope.global(), scope_ref_id: ref] ++ opts
        ),
      else: :invalid
  end

  @doc false
  def serialize(%Bans.Ban{} = ban) do
    %{
      id: ban.id,
      kind: to_string(ban.kind),
      subject: ban.subject,
      user_id: ban.user_id || "",
      scope: ban.scope || "",
      scope_ref_id: ban.scope_ref_id || "",
      user_name: name(ban.user),
      expires_at: ban.expires_at,
      reason: ban.reason || "",
      source: to_string(ban.source),
      banned_by: ban.banned_by || "",
      banned_by_name: name(ban.banned_by_user),
      lifted_at: ban.lifted_at,
      lifted_by: ban.lifted_by || "",
      lifted_by_name: name(ban.lifted_by_user),
      active: Bans.active?(ban),
      inserted_at: ban.inserted_at,
      updated_at: ban.updated_at
    }
  end

  defp name(%{display_name: name}) when is_binary(name), do: name
  defp name(_user), do: ""

  defp expires_at(nil), do: {:ok, nil}
  defp expires_at(""), do: {:ok, nil}

  defp expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _ -> :error
    end
  end

  defp expires_at(_value), do: :error

  defp invalid_id(conn), do: reply_error(conn, :bad_request, "invalid_id")
end
