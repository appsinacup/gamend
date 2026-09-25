defmodule GamendWeb.LiveHelpers do
  @moduledoc """
  Shared helpers for LiveViews.
  """

  use Gettext, backend: GamendWeb.Gettext

  alias Gamend.Captcha

  # ── Pagination ──────────────────────────────────────────────────────────
  #
  # Eighteen LiveViews each wrote their own prev/next/page-size handlers, and
  # the copies had drifted into bugs: eleven parsed the size with
  # `String.to_integer/1`, so a non-numeric value crashed the page and any
  # number bypassed `Gamend.Limits`; six never clamped "next", so it paged past
  # the end into empty results; one clamped to `total_pages` without a floor, so
  # an empty list put the reader on page 0. These do the arithmetic once. Each
  # page still reloads its own way, so they return the socket rather than doing
  # the reload.

  @doc "See `GamendWeb.Pagination.total_pages/2`."
  defdelegate total_pages(total_count, page_size), to: GamendWeb.Pagination

  @doc """
  Steps back one page, never below the first.

  `key` is the assign holding the page number, for a view that pages more than
  one list.
  """
  @spec prev_page(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  def prev_page(socket, key \\ :page) do
    Phoenix.Component.assign(socket, key, max(socket.assigns[key] - 1, 1))
  end

  @doc """
  Steps forward one page — no further than the last, when the view knows how
  many there are, and never onto page 0 when there are none.

  The total is read from `total_key`, which defaults to the page key's partner
  by the convention every view here follows: `:page` pairs with `:total_pages`,
  `:records_page` with `:records_total_pages`. Deriving it matters: a fixed
  `:total_pages` default would clamp a view's *second* list against its first
  list's total.
  """
  @spec next_page(Phoenix.LiveView.Socket.t(), atom(), atom() | nil) ::
          Phoenix.LiveView.Socket.t()
  def next_page(socket, key \\ :page, total_key \\ nil) do
    total_key = total_key || total_key_for(key)
    page = socket.assigns[key] + 1

    page =
      case socket.assigns[total_key] do
        total when is_integer(total) -> min(page, max(total, 1))
        _unknown -> page
      end

    Phoenix.Component.assign(socket, key, page)
  end

  defp total_key_for(:page), do: :total_pages

  # An atom no view has ever created cannot name an assign the socket holds, so
  # a view that pages without tracking a total simply has none: unbounded.
  defp total_key_for(key) do
    key
    |> Atom.to_string()
    |> String.replace_suffix("_page", "_total_pages")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  @doc """
  Applies a requested page size and returns to the first page.

  The raw value is whatever the form sent. It is parsed and clamped by
  `Gamend.Limits.clamp_page_size/2`, so a malformed value keeps the current size
  instead of crashing the view, and no value exceeds the configured maximum.
  `:min` raises the floor for a layout that needs a minimum (a card grid).
  `:size_key` and `:page_key` name the assigns, for a view paging more than one
  list (`:lobbies_page_size` and `:lobbies_page`, say).
  """
  @spec put_page_size(Phoenix.LiveView.Socket.t(), term(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def put_page_size(socket, raw, opts \\ []) do
    size_key = Keyword.get(opts, :size_key, :page_size)

    size =
      raw
      |> Gamend.Limits.clamp_page_size(socket.assigns[size_key] || 25)
      |> max(Keyword.get(opts, :min, 1))

    socket
    |> Phoenix.Component.assign(size_key, size)
    |> Phoenix.Component.assign(Keyword.get(opts, :page_key, :page), 1)
  end

  @doc """
  The client IP for a `live_session`'s `:session` MFA, resolved on the HTTP
  request.

  That request has been through `GamendWeb.Plugs.RealIp`, so `remote_ip` is
  the client behind the proxy rather than the proxy. The socket's own
  `peer_data` is not: behind a reverse proxy it is the proxy for every
  visitor, and the longpoll transport has none at all. The session is signed
  into the page, so a client cannot choose the address it is limited under.
  """
  @spec client_ip_session(Plug.Conn.t()) :: %{String.t() => String.t()}
  def client_ip_session(%Plug.Conn{remote_ip: ip}) do
    %{"client_ip" => ip |> :inet.ntoa() |> to_string()}
  end

  @doc """
  The client IP a LiveView rate-limits under.

  Read from the session `client_ip_session/1` signed into the page, falling
  back to the socket's peer data and then to `"unknown"`, which is a bucket
  like any other rather than a pass.
  """
  @spec client_ip(Phoenix.LiveView.Socket.t(), map()) :: String.t()
  def client_ip(socket, session) do
    case session do
      %{"client_ip" => ip} when is_binary(ip) -> ip
      _ -> peer_ip(socket)
    end
  end

  defp peer_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: addr} -> addr |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  @doc """
  Check a rate limit bucket for the given IP.

  Bucket types, sharing the HTTP limiter's settings:
    - `:auth` — `auth_limit` per `auth_window_ms`
    - `:general` — `general_limit` per `general_window_ms`

  Returns `:ok` or `{:error, retry_after_ms}`.
  """
  def check_rate_limit(ip, bucket_type \\ :general)

  def check_rate_limit(ip, :auth) do
    {limit, window} = auth_limits()
    do_check("lv_auth:#{GamendWeb.RateLimit.ip_key(ip)}", window, limit)
  end

  def check_rate_limit(ip, :general) do
    {limit, window} = general_limits()
    do_check("lv_general:#{GamendWeb.RateLimit.ip_key(ip)}", window, limit)
  end

  defp do_check(key, window_ms, limit) do
    case GamendWeb.RateLimit.hit(key, window_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after} -> {:error, retry_after}
    end
  end

  defp auth_limits do
    {setting(:auth_limit), setting(:auth_window_ms)}
  end

  defp general_limits do
    {setting(:general_limit), setting(:general_window_ms)}
  end

  defp setting(key), do: Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, key)

  @doc """
  Verify the captcha token carried by a `phx-submit`'s params.

  Returns `:ok` — including whenever the captcha is disabled, so a call site
  needs no `enabled?/0` branch of its own — or `{:error, socket}` with the
  failure already handled: a flash explaining which way it failed, and a reset
  pushed to the widget. The reset is not optional. A token Cloudflare rejected
  is spent, so without it the form would resubmit the same dead token forever
  and the player could never recover without a reload.

  Pair it with `<.captcha>` in the form (see `GamendWeb.CoreComponents`),
  and read `:client_ip` off the socket, which both auth LiveViews assign at
  mount.
  """
  @spec check_captcha(Phoenix.LiveView.Socket.t(), map()) ::
          :ok | {:error, Phoenix.LiveView.Socket.t()}
  def check_captcha(socket, params) when is_map(params) do
    case Captcha.verify(params["cf-turnstile-response"], socket.assigns[:client_ip]) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         socket
         |> Phoenix.LiveView.put_flash(:error, captcha_error(reason))
         |> Phoenix.LiveView.push_event("captcha:reset", %{})}
    end
  end

  defp captcha_error(:missing), do: gettext("Please complete the captcha.")

  # Split from :missing so a player who did complete it is not told to do the
  # thing they just did.
  defp captcha_error(:invalid), do: gettext("Captcha check failed. Please try again.")

  defp captcha_error(:unavailable),
    do: gettext("Could not reach the captcha service. Please try again.")

  @doc """
  Put a standard success flash on a LiveView socket.
  """
  def put_success(socket, message), do: Phoenix.LiveView.put_flash(socket, :info, message)

  @doc """
  Put a standard error flash on a LiveView socket.
  """
  def put_failure(socket, message), do: Phoenix.LiveView.put_flash(socket, :error, message)

  @doc """
  The flash for a failed action: `reason`'s readable text when
  `error_message/1` knows it, else `prefix` alone.

  This used to append `inspect(reason)`, which showed players `:group_full` or
  a raw Ecto error list. A reason with no player-facing text now shows only the
  prefix (usually "Failed").
  """
  @spec failure_message(String.t(), term()) :: String.t()
  def failure_message(prefix, reason), do: error_message(reason) || prefix

  @doc """
  Readable text for an `{:error, reason}` a player can act on, or `nil` when the
  reason is internal and the caller should fall back to a generic message.

  A changeset gives its first error, translated like a form error. A hook
  rejection that carries a string is the game's own words and is shown as is.
  """
  @spec error_message(term()) :: String.t() | nil
  def error_message(%Ecto.Changeset{errors: [{_field, error} | _]}),
    do: GamendWeb.CoreComponents.translate_error(error)

  def error_message({:hook_rejected, reason}) when is_binary(reason) and reason != "",
    do: reason

  def error_message({:hook_rejected, _reason}), do: gettext("Not allowed")

  def error_message(reason) when reason in [:not_authorized, :forbidden, :disallowed],
    do: gettext("Not allowed")

  def error_message(reason) when reason in [:not_found, :party_not_found],
    do: gettext("Not found")

  def error_message(:user_not_found), do: gettext("Player not found.")

  def error_message(reason)
      when reason in [
             :cannot_friend_self,
             :cannot_block_self,
             :cannot_kick_self,
             :cannot_promote_self,
             :cannot_demote_self
           ],
      do: gettext("You cannot do that to yourself.")

  def error_message(:blocked), do: gettext("One of you has blocked the other.")
  def error_message(:already_friends), do: gettext("You are already friends.")
  def error_message(:already_requested), do: gettext("You already sent a request.")
  def error_message(:too_many_friends), do: gettext("Your friend list is full.")

  def error_message(reason)
      when reason in [:too_many_pending_requests, :too_many_pending_invites],
      do: gettext("Too many pending requests. Wait for some to be answered.")

  def error_message(:not_connected),
    do: gettext("You can only invite friends or players who share a group with you.")

  def error_message(:not_admin), do: gettext("Only a group admin can do that.")

  def error_message(reason) when reason in [:not_member, :not_in_group],
    do: gettext("You are not a member of this group.")

  def error_message(:already_member), do: gettext("Already a member.")
  def error_message(:already_admin), do: gettext("Already an admin.")
  def error_message(:last_admin), do: gettext("Make someone else an admin first.")
  def error_message(:too_many_groups_created), do: gettext("You have created too many groups.")

  def error_message(reason) when reason in [:max_members_too_low, :too_small],
    do: gettext("That is fewer than the current number of members.")

  def error_message(reason) when reason in [:full, :party_full, :tournament_full],
    do: gettext("It is full.")

  def error_message(:not_pending), do: gettext("This was already answered.")
  def error_message(:no_invite), do: gettext("The invite is no longer valid.")
  def error_message(:already_in_lobby), do: gettext("You are already in a lobby.")
  def error_message(:not_in_lobby), do: gettext("You are not in this lobby.")
  def error_message(:not_host), do: gettext("Only the host can do that.")
  def error_message(:locked), do: gettext("It is locked.")
  def error_message(:password_required), do: gettext("A password is required.")
  def error_message(:invalid_password), do: gettext("Wrong password.")
  def error_message(:already_in_party), do: gettext("You are already in a party.")
  def error_message(:not_in_party), do: gettext("You are not in a party.")
  def error_message(:not_leader), do: gettext("Only the party leader can do that.")
  def error_message(:already_invited), do: gettext("Already invited.")
  def error_message(:muted), do: gettext("You are muted.")
  def error_message(:slowdown), do: gettext("You are sending messages too fast.")
  def error_message(:blocked_content), do: gettext("That message is not allowed.")
  def error_message(:not_friends), do: gettext("You can only message friends.")
  def error_message(:already_registered), do: gettext("You are already registered.")
  def error_message(:not_registered), do: gettext("You are not registered.")
  def error_message(:registration_closed), do: gettext("Registration is closed.")
  def error_message(_reason), do: nil

  # ── Payment labels ──────────────────────────────────────────────────────
  #
  # Payments store lowercase codes ("stripe", "requires_action",
  # "subscription"). The store and the Payments tab showed them raw.

  @doc "The store a purchase went through, as a brand name."
  def payment_provider_label("stripe"), do: "Stripe"
  def payment_provider_label("apple"), do: "Apple"
  def payment_provider_label("google"), do: "Google Play"
  def payment_provider_label("steam"), do: "Steam"
  def payment_provider_label(provider), do: provider

  @doc "A product kind (`Gamend.Payments.Product`) in words."
  def payment_kind_label("entitlement"), do: gettext("One-time")
  def payment_kind_label("consumable"), do: gettext("Consumable")
  def payment_kind_label("subscription"), do: gettext("Subscription")
  def payment_kind_label(kind), do: kind

  @doc "A purchase or entitlement status in words."
  def payment_status_label("pending"), do: gettext("Pending")
  def payment_status_label("requires_action"), do: gettext("Awaiting payment")
  def payment_status_label("completed"), do: gettext("Completed")
  def payment_status_label("failed"), do: gettext("Failed")
  def payment_status_label("cancelled"), do: gettext("Cancelled")
  def payment_status_label("refunded"), do: gettext("Refunded")
  def payment_status_label("revoked"), do: gettext("Revoked")
  def payment_status_label("active"), do: gettext("Active")
  def payment_status_label("expired"), do: gettext("Expired")
  def payment_status_label(status), do: status

  @doc """
  How a LiveView names a user it may only hold as a loaded struct, a serialized
  map, or a bare id. Never an email address.

  A struct or an id goes through `Gamend.Accounts.display_name/1`. A serialized
  map (string or atom keys) has no struct to hand over, so its fields are read
  directly by the same rule: display name, else username.

  This used to end at `"User <id>"` — the one fallback
  `Gamend.Accounts.display_label/1` documents as wrong, because it reads like a
  name while telling the reader nothing. An unresolvable user is `""` now.
  """
  def public_user_name(nil), do: ""
  def public_user_name(%Gamend.Accounts.User{} = user), do: Gamend.Accounts.display_name(user)
  def public_user_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{"display_name" => name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{username: name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{"username" => name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{id: id}) when is_binary(id), do: Gamend.Accounts.display_name(id)
  def public_user_name(%{"id" => id}) when is_binary(id), do: Gamend.Accounts.display_name(id)
  def public_user_name(%{user_id: id}) when is_binary(id), do: Gamend.Accounts.display_name(id)

  def public_user_name(%{"user_id" => id}) when is_binary(id),
    do: Gamend.Accounts.display_name(id)

  def public_user_name(id) when is_binary(id), do: Gamend.Accounts.display_name(id)
  def public_user_name(_), do: ""

  @doc """
  Return the public `@username` handle for a user, or `nil` when the user has
  none (renders as empty in HEEx, so callers can interpolate it directly).
  """
  def public_user_handle(%{username: name}) when is_binary(name) and name != "", do: "@" <> name

  def public_user_handle(%{"username" => name}) when is_binary(name) and name != "",
    do: "@" <> name

  def public_user_handle(_), do: nil
end
