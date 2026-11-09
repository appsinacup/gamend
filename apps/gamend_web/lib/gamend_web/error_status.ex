defmodule GamendWeb.ErrorStatus do
  @moduledoc """
  The HTTP status each error reason means, one table for every API controller
  (docs/specs/api-conventions.md, "The status follows the reason", R18).

  A context fails with an atom and its `@spec` names it. The controller answers
  it in one of two ways:

      {:error, :lobby_not_found} -> reply_error(conn, :not_found, "lobby_not_found")
      {:error, reason} -> reply_reason(conn, reason)

  `GamendWeb.Reply.reply_reason/2` looks the atom up here and answers with its
  name as the code. A new reason needs no controller change: name it so a rule
  below covers it, or add a line to the table. A reason with no status raises
  `GamendWeb.UnmappedReason`, a 500 whose log names the atom, instead of the
  400 or 403 a catch-all clause used to make up for it. A controller that
  answers a reason with another code (`:invalid` as `captcha_invalid`) keeps a
  clause of its own before the fallback.

  Names the table need not list:

  - `*_not_found` is 404;
  - `already_*` and `*_already_*` are 409: what was asked for already holds;
  - `*_not_configured` is 503: the server, not the request, lacks something.

  `mix gamend.api.lint` (R18) holds an explicit
  `reply_error(conn, status, "code")` to the same status when the code is a
  reason this module knows. Words that mean different things in different
  places (`:invalid`, `:missing`, `:disabled`, `:unavailable`) are left out on
  purpose: each controller says what it means.
  """

  @statuses %{
    # 400: the request is malformed.
    cannot_block_self: :bad_request,
    cannot_friend_self: :bad_request,
    cannot_notify_self: :bad_request,
    invalid_chat_ref: :bad_request,
    invalid_chat_type: :bad_request,
    invalid_count: :bad_request,
    invalid_currency: :bad_request,
    invalid_id: :bad_request,
    invalid_item: :bad_request,
    last_auth_method: :bad_request,
    last_provider: :bad_request,
    missing_recipient: :bad_request,
    own_message: :bad_request,
    too_many_tokens: :bad_request,

    # 401: the credentials are wrong.
    invalid_code: :unauthorized,
    invalid_credentials: :unauthorized,

    # 403: a refusal. The request is understood and the answer is no.
    account_required: :forbidden,
    blocked: :forbidden,
    cannot_demote_self: :forbidden,
    cannot_kick_self: :forbidden,
    cannot_promote_self: :forbidden,
    email_not_confirmed: :forbidden,
    forbidden: :forbidden,
    full: :forbidden,
    insufficient_funds: :forbidden,
    insufficient_items: :forbidden,
    invalid_password: :forbidden,
    last_admin: :forbidden,
    leaderboard_ended: :forbidden,
    links_off: :forbidden,
    lobby_too_small_for_party: :forbidden,
    locked: :forbidden,
    members_offline: :forbidden,
    muted: :forbidden,
    not_admin: :forbidden,
    not_authorized: :forbidden,
    not_cancelled: :forbidden,
    not_completed: :forbidden,
    not_connected: :forbidden,
    not_enough_space: :forbidden,
    not_friends: :forbidden,
    not_host: :forbidden,
    not_in_group: :forbidden,
    not_leader: :forbidden,
    not_owner: :forbidden,
    not_party_leader: :forbidden,
    not_pending: :forbidden,
    not_private: :forbidden,
    not_public: :forbidden,
    party_full: :forbidden,
    password_required: :forbidden,
    quest_limit_reached: :forbidden,
    too_many_entries: :forbidden,
    too_many_filter_words: :forbidden,
    too_many_codes: :forbidden,
    too_many_friends: :forbidden,
    too_many_groups: :forbidden,
    too_many_groups_created: :forbidden,
    too_many_notifications: :forbidden,
    too_many_pending_invites: :forbidden,
    too_many_pending_requests: :forbidden,

    # 404: the thing is not there, the caller's own current one included.
    invalid_lobby: :not_found,
    no_invite: :not_found,
    no_open_check: :not_found,
    not_a_participant: :not_found,
    not_found: :not_found,
    not_in_lobby: :not_found,
    not_in_party: :not_found,
    not_member: :not_found,
    unknown_language: :not_found,

    # 409: the state the request depends on is not the one it found.
    contended: :conflict,
    member_in_lobby: :conflict,
    not_revocable: :conflict,
    state_changed: :conflict,

    # 413, 415, 422, 429, 507.
    too_large: :request_entity_too_large,
    content_mismatch: :unsupported_media_type,
    unsupported_content_type: :unsupported_media_type,
    blocked_content: :unprocessable_entity,
    invalid_state: :unprocessable_entity,
    max_members_too_low: :unprocessable_entity,
    message_not_in_chat: :unprocessable_entity,
    no_participants: :unprocessable_entity,
    not_code_only: :unprocessable_entity,
    too_many_participants: :unprocessable_entity,
    too_small: :unprocessable_entity,
    chat_daily_limit: :too_many_requests,
    redeem_rate_limit: :too_many_requests,
    report_daily_limit: :too_many_requests,
    slowdown: :too_many_requests,
    quota_exceeded: :insufficient_storage
  }

  @doc "The status `reason` means, or `nil` when neither the table nor its name says."
  @spec status(atom()) :: atom() | nil
  def status(reason) when is_atom(reason) do
    Map.get(@statuses, reason) || by_name(Atom.to_string(reason))
  end

  @doc "The table, for `mix gamend.api.lint`."
  @spec statuses() :: %{atom() => atom()}
  def statuses, do: @statuses

  defp by_name(name) do
    cond do
      String.ends_with?(name, "_not_found") -> :not_found
      String.starts_with?(name, "already_") or String.contains?(name, "_already_") -> :conflict
      String.ends_with?(name, "_not_configured") -> :service_unavailable
      true -> nil
    end
  end
end
