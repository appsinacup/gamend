defmodule GamendWeb.Api.V1.ReadyCheckController do
  @moduledoc """
  The one client-facing surface for ready checks.

  A player holds at most one open check per lane — the match lane (lobby
  ready-up or matchmaking accept) and the party lane (the party's standing
  board) — so answering needs no id, just a `scope`. `GET /me/ready_check`
  returns both lanes; `POST /me/ready_check` answers one of them.

  `POST /lobbies/ready_check` and `POST /parties/ready_check` are **reset**
  semantics: they quietly replace any open board with a fresh one over the
  current members, so the same endpoint serves "open", "force ready" (pass a
  `timeout_ms`) and "start over".
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.ControllerScope

  alias Gamend.Lobbies
  alias Gamend.Parties
  alias Gamend.ReadyChecks
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    MyReadyChecksResponse,
    OkResponse,
    ReadyCheckStateResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Ready checks"])

  operation(:show,
    operation_id: "get_my_ready_check",
    summary: "Get the caller's open ready checks",
    description:
      "Returns the caller's open check per lane — `lobby` (the match lane: " <>
        "lobby ready-up or matchmaking accept) and `party` (the party board) — " <>
        "each null when there is none. A kind=ready check lists every " <>
        "participant; a kind=accept check returns counts and the caller's own " <>
        "state only.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Open ready checks per lane", "application/json", MyReadyChecksResponse},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def show(conn, _params) do
    with_user(conn, fn user ->
      reply_data(conn, %{
        lobby: serialize(ReadyChecks.for_user(user.id, :match), user),
        party: serialize(ReadyChecks.for_user(user.id, :party), user)
      })
    end)
  end

  operation(:respond,
    operation_id: "respond_ready_check",
    summary: "Answer one of the caller's open ready checks",
    description:
      "`ready: true` is ready/accept, `false` is not-ready/decline. `scope` " <>
        "picks the lane: \"lobby\" (default — also answers a matchmaking " <>
        "accept) or \"party\". In a kind=ready check the answer can be flipped " <>
        "freely; in a kind=accept check it is final (`not_revocable`, 409), and a " <>
        "decline fails the check for everyone. No open check in that lane is 404 " <>
        "`no_open_check`.",
    security: [%{"authorization" => []}],
    request_body: {
      "The answer",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          ready: %Schema{type: :boolean},
          scope: %Schema{type: :string, enum: ["lobby", "party"], default: "lobby"}
        },
        required: [:ready]
      }
    },
    responses: [
      ok: {"The check after the answer", "application/json", ReadyCheckStateResponse},
      bad_request: Schemas.error("Missing or invalid ready flag or scope"),
      not_found: Schemas.error("No open check in that lane"),
      conflict: Schemas.error("The answer is final, or the check already resolved"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def respond(conn, %{"ready" => ready} = params) when is_boolean(ready) do
    with_user(conn, fn user ->
      case parse_scope(Map.get(params, "scope", "lobby")) do
        {:ok, scope} -> do_respond(conn, user, ready, scope)
        :error -> reply_error(conn, :bad_request, "invalid_scope")
      end
    end)
  end

  def respond(conn, _params),
    do: reply_error(conn, :bad_request, "invalid_ready")

  defp do_respond(conn, user, ready, scope) do
    # `no_open_check` and `not_a_participant` (taken off the board by a leave
    # on the way) are 404; `not_revocable` and `already_resolved` 409.
    case ReadyChecks.respond(user, ready, scope) do
      {:ok, check} -> reply_data(conn, serialize(check, user))
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  operation(:open,
    operation_id: "open_lobby_ready_check",
    summary: "Open (or reset) the ready board in the caller's lobby (host only)",
    description:
      "Allowed only for the host of a host-managed lobby: hostless (matchmaking) " <>
        "lobbies belong to the server, so no player may open one there. Every current " <>
        "member becomes a participant and the host is pre-marked ready — clicking the " <>
        "button is their answer. An already-open board is quietly replaced (reset), " <>
        "so the same call serves 'ready check!', 'force ready' (with timeout_ms) " <>
        "and 'start over'. Core never kicks or starts anything on the result.",
    security: [%{"authorization" => []}],
    request_body: {
      "Options",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          timeout_ms: %Schema{
            type: :integer,
            description: "Answering window; omit for the configured default"
          },
          metadata: %Schema{type: :object, description: "Echoed to clients"}
        }
      }
    },
    responses: [
      created: {"The open check", "application/json", ReadyCheckStateResponse},
      not_found: Schemas.error("Not in a lobby (not_in_lobby), or it went away (not_found)"),
      forbidden: Schemas.error("Not the host, the lobby is hostless, or a hook refused"),
      conflict: Schemas.error("A member is locked in another check"),
      unprocessable_entity: Schemas.error("No participants, or too many"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def open(conn, params) do
    with_lobby(conn, fn user, lobby ->
      if Lobbies.can_manage_lobby?(user, lobby) do
        do_reset(conn, user, lobby, params)
      else
        reply_error(conn, :forbidden, "not_host")
      end
    end)
  end

  operation(:open_party,
    operation_id: "open_party_ready_check",
    summary: "Open (or reset) the ready board in the caller's party (leader only)",
    description:
      "Every current member becomes a participant and the leader is pre-marked " <>
        "ready. An already-open board is quietly replaced (reset), so the same " <>
        "call serves 'ready up!', 'force ready' (with timeout_ms) and " <>
        "'start over'. The party board is independent of any lobby check.",
    security: [%{"authorization" => []}],
    request_body: {
      "Options",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          timeout_ms: %Schema{
            type: :integer,
            description: "Answering window; omit for the configured default"
          },
          metadata: %Schema{type: :object, description: "Echoed to clients"}
        }
      }
    },
    responses: [
      created: {"The open check", "application/json", ReadyCheckStateResponse},
      not_found: Schemas.error("Not in a party (not_in_party), or it went away (not_found)"),
      forbidden: Schemas.error("Not the party leader, or a hook refused"),
      conflict: Schemas.error("A member is locked in another check"),
      unprocessable_entity: Schemas.error("No participants, or too many"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def open_party(conn, params) do
    with_party(conn, fn user, party ->
      if Parties.can_manage_party?(user, party) do
        # A party board STANDS: it is the crew's answer to "are you coming",
        # asked once and left up, not a countdown gating a match start the way a
        # lobby board is. Without this it inherited the lobby default (20s), and
        # a crew member who looked away lost the board out from under both of
        # them — an expired check reports no participants, so the crew's button
        # went to a disabled "Waiting for the captain" and the leader's to a
        # disabled "Waiting for crew", with nothing left to reopen it. A caller
        # that genuinely wants a fuse still gets one by sending timeout_ms.
        do_reset(conn, user, party, params, nil)
      else
        reply_error(conn, :forbidden, "not_leader")
      end
    end)
  end

  # Every member, read again under the subject's lock as the board is written
  # (`:members`): read here, a member who left before the write stayed on it.
  defp do_reset(conn, user, subject, params, default_timeout_ms \\ :subject_default) do
    opts =
      [opened_by: user.id, metadata: Map.get(params, "metadata", %{})]
      |> maybe_timeout(Map.get(params, "timeout_ms"), default_timeout_ms)

    # `already_pending` is 409, `no_participants` and `too_many_participants`
    # 422, a game hook's veto 403 `rejected`, and a subject deleted since it
    # was read 404 `not_found`.
    case ReadyChecks.reset(subject, :members, opts) do
      {:ok, check} -> reply_data(conn, :created, serialize(check, user))
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  operation(:cancel,
    operation_id: "cancel_lobby_ready_check",
    summary: "Call off the ready check in the caller's lobby (host only)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Cancelled", "application/json", OkResponse},
      forbidden: Schemas.error("Not the host, or the lobby is hostless"),
      not_found: Schemas.error("Not in a lobby (not_in_lobby), or no open check (no_open_check)"),
      conflict: Schemas.error("The check passed or failed before the cancel (already_resolved)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def cancel(conn, _params) do
    with_lobby(conn, fn user, lobby ->
      if Lobbies.can_manage_lobby?(user, lobby) do
        do_cancel(conn, ReadyChecks.pending_for_lobby(lobby.id))
      else
        reply_error(conn, :forbidden, "not_host")
      end
    end)
  end

  # One read of the open check, then the cancel answers from its own lock: the
  # last answer can pass the check in between, and then nothing was cancelled.
  # That answered 500 (`:ok =` on the error).
  defp do_cancel(conn, nil), do: reply_error(conn, :not_found, "no_open_check")

  defp do_cancel(conn, check) do
    case ReadyChecks.cancel(check) do
      {:ok, _check} -> reply_ok(conn)
      {:error, :already_resolved} -> reply_error(conn, :conflict, "already_resolved")
      {:error, :no_open_check} -> reply_error(conn, :not_found, "no_open_check")
    end
  end

  operation(:cancel_party,
    operation_id: "cancel_party_ready_check",
    summary: "Call off the ready check in the caller's party (leader only)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Cancelled", "application/json", OkResponse},
      forbidden: Schemas.error("Not the party leader"),
      not_found: Schemas.error("Not in a party (not_in_party), or no open check (no_open_check)"),
      conflict: Schemas.error("The check passed or failed before the cancel (already_resolved)"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def cancel_party(conn, _params) do
    with_party(conn, fn user, party ->
      if Parties.can_manage_party?(user, party) do
        do_cancel(conn, ReadyChecks.pending_for_party(party.id))
      else
        reply_error(conn, :forbidden, "not_leader")
      end
    end)
  end

  defp parse_scope("lobby"), do: {:ok, :match}
  defp parse_scope("party"), do: {:ok, :party}
  defp parse_scope(_scope), do: :error

  defp serialize(check, user), do: Serializers.serialize_ready_check(check, viewer_id: user.id)

  # What the caller asked for always wins. Otherwise the subject decides:
  # `:subject_default` leaves the option off entirely, so ReadyChecks applies
  # its own `ready_check_timeout_ms`; an explicit `nil` opens a board with no
  # deadline at all (see open_party).
  defp maybe_timeout(opts, ms, _default) when is_integer(ms) and ms > 0,
    do: Keyword.put(opts, :timeout_ms, ms)

  defp maybe_timeout(opts, _ms, :subject_default), do: opts

  defp maybe_timeout(opts, _ms, default), do: Keyword.put(opts, :timeout_ms, default)
end
