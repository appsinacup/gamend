defmodule GamendWeb.UserAuth do
  @moduledoc """
  Helpers for session / cookie based authentication and LiveView mounts.

  This module provides routines used by controllers and LiveViews to manage
  user sessions, remember-me cookies, and `on_mount` helpers for mounting the
  authenticated `current_scope` for LiveViews.
  """
  use GamendWeb, :verified_routes

  use Gettext, backend: GamendWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.UserToken

  require Logger

  # The remember-me cookie lives exactly as long as the session token it holds:
  # both come from `auth.session_days` (`UserToken.session_validity_in_days/0`).
  @remember_me_cookie "_gamend_web_user_remember_me"

  # The anonymous account a LiveView makes travels to the browser as this,
  # encrypted, and comes back to `put_anonymous_session/2` within the age.
  @anonymous_session_salt "anonymous session"
  @anonymous_session_max_age 300

  @doc """
  The remember-me cookie that signs `token` in, as `{name, value}`: what a
  browser holds after "Keep me signed in". `mix demo.bench` hands it to its
  page client, which has no other way to sign in.
  """
  @spec remember_me_cookie(binary()) :: {String.t(), String.t()}
  def remember_me_cookie(token) when is_binary(token) do
    secret = Application.fetch_env!(:gamend_web, GamendWeb.Endpoint)[:secret_key_base]

    # What `put_resp_cookie(conn, name, token, sign: true, max_age: ...)` in
    # `write_remember_me_cookie/2` sends, without a conn to send it on.
    value =
      Plug.Crypto.sign(secret, @remember_me_cookie <> "_cookie", token,
        keys: Plug.Keys,
        max_age: session_seconds()
      )

    {@remember_me_cookie, value}
  end

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.

  Signing in on the website is how an account scheduled for deletion is kept:
  a person is at the keyboard here, where an API sign-in may be a game client
  signing in on its own (`GamendWeb.Auth.Tokens.refusal/1`).
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)
    replaced_guest = replaced_anonymous_user(conn, user)
    {conn, user} = keep_scheduled_account(conn, user)

    conn = create_or_extend_session(conn, user, params)

    # A guest who signs in to an account they already have brings what they
    # did with them: it is merged into the account, never over it
    # (`Accounts.GuestMerge`), in this request so the first page shows it.
    # The guest account, which nothing can reach again once this session is
    # replaced, is then deleted (through `Accounts.delete_user/1`, so plugins
    # clean up after it).
    if replaced_guest do
      Accounts.GuestMerge.merge(replaced_guest, user)
      Gamend.Async.run(fn -> Accounts.delete_user(replaced_guest) end)
    end

    # Fire-and-forget login hook for non-token logins (magic-link tokens are
    # handled specially in Accounts.login_user_by_magic_link so they already
    # trigger the hook there). Skip double-invocation when params contain
    # a magic-link "token" key.
    unless Map.has_key?(params || %{}, "token") do
      # Use safe wrapper for hook invocation so missing hooks don't crash background tasks
      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_user_logged_in, [user])
        # The quest event travels with the hook: password and OAuth logins land
        # here, and only the magic-link path (Accounts) emits it itself — without
        # this, "log in" quests never progressed for most sign-ins.
        Gamend.Quests.report_event(user.id, "login")
      end)
    end

    conn |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp replaced_anonymous_user(conn, %Accounts.User{id: id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %Accounts.User{id: previous_id} = previous when previous_id != id ->
        if Accounts.User.anonymous?(previous), do: previous

      _ ->
        nil
    end
  end

  defp keep_scheduled_account(conn, user) do
    if Accounts.deletion_scheduled?(user) do
      case Accounts.cancel_deletion(user) do
        {:ok, user} ->
          {put_flash(conn, :info, gettext("Welcome back. Your account will not be deleted.")),
           user}

        {:error, _changeset} ->
          {conn, user}
      end
    else
      {conn, user}
    end
  end

  @doc """
  The caller's account, made for them when they have none.

  A signed-out visitor stays signed out until a page needs to save something
  for them — tapping a route, finishing a test — and the page calls this
  first. It creates an anonymous account the way a game client gets one: a
  device account (`Accounts.find_or_create_from_device/2`), on a device id the
  server makes up since a browser has none to send, so only while
  `device_auth_enabled` is on. It assigns its scope so the action
  goes through on this socket, and pushes `gamend:anonymous_session` to the
  browser with the session token, encrypted. A LiveView cannot write the session
  cookie itself, so `app.js` posts that token to `/users/anonymous_session`
  (`put_anonymous_session/2`) and reconnects the socket, which then mounts every
  page with the account.

  Creating on demand rather than on every visit is deliberate: a crawler or a
  reader who only looks never gets an account row. When to call it is the
  page's decision.

  Returns `{:ok, socket}` with `current_scope` set, or `{:error, reason}`:
  `:disabled` when device accounts are off, `:not_connected` on the static render
  (there is no browser to hand the session to yet), `:rate_limited` past the
  per-IP limit on new accounts (the general bucket page loads use). Every
  refusal is logged with the page's view: a page carries on signed out, so
  the log (admin Logs) is the only place it shows.
  """
  @spec ensure_user(Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, term()}
  def ensure_user(%Phoenix.LiveView.Socket{} = socket) do
    cond do
      Scope.user(socket.assigns[:current_scope]) ->
        {:ok, socket}

      not Phoenix.LiveView.connected?(socket) ->
        log_guest_refused({:error, :not_connected}, inspect(socket.view))

      true ->
        with :ok <- guest_rate_limit(socket.assigns[:client_ip]),
             {:ok, user} <- Accounts.find_or_create_from_device(web_device_id()) do
          token = Accounts.generate_user_session_token(user)

          {:ok,
           socket
           |> Phoenix.Component.assign(:current_scope, Scope.for_user(user))
           |> Phoenix.LiveView.push_event("gamend:anonymous_session", %{
             token: encrypt_anonymous_session(token)
           })}
        else
          error -> log_guest_refused(error, inspect(socket.view))
        end
    end
  end

  @doc """
  `ensure_user/1` for a controller: the same anonymous account, written to the
  session and the remember-me cookie straight away, since a plain request can.
  """
  @spec ensure_user_conn(Plug.Conn.t()) :: {:ok, Plug.Conn.t()} | {:error, term()}
  def ensure_user_conn(%Plug.Conn{} = conn) do
    if Scope.user(conn.assigns[:current_scope]) do
      {:ok, conn}
    else
      with :ok <- guest_rate_limit(conn.remote_ip |> :inet.ntoa() |> to_string()),
           {:ok, user} <- Accounts.find_or_create_from_device(web_device_id()) do
        token = Accounts.generate_user_session_token(user)

        {:ok,
         conn
         |> put_token_in_session(token)
         |> write_remember_me_cookie(token)
         |> assign(:current_scope, Scope.for_user(user))}
      else
        error -> log_guest_refused(error, conn.request_path)
      end
    end
  end

  @doc """
  Writes the anonymous account `ensure_user/1` made into this browser's session.

  The token must decrypt, be recent, and name a live session of an anonymous
  account. A browser already signed in with a real account keeps it: an
  anonymous session never replaces one. The rest of the session (locale,
  visitor id, the CSRF token the socket reconnects with) is kept, so there is
  no `renew_session/2` here.
  """
  @spec put_anonymous_session(Plug.Conn.t(), String.t()) :: {:ok, Plug.Conn.t()} | :error
  def put_anonymous_session(%Plug.Conn{} = conn, encrypted) when is_binary(encrypted) do
    with {:ok, token} <-
           Phoenix.Token.decrypt(GamendWeb.endpoint(), @anonymous_session_salt, encrypted,
             max_age: @anonymous_session_max_age
           ),
         true <- is_binary(token),
         {%Accounts.User{} = user, _inserted_at} <- Accounts.get_user_by_session_token(token),
         true <- Accounts.User.anonymous?(user) do
      current = Scope.user(conn.assigns[:current_scope])

      if current && not Accounts.User.anonymous?(current) do
        {:ok, conn}
      else
        {:ok, conn |> put_token_in_session(token) |> write_remember_me_cookie(token)}
      end
    else
      _ -> :error
    end
  end

  def put_anonymous_session(_conn, _encrypted), do: :error

  # A new guest account counts in the normal per-IP bucket (`general_limit`
  # per `general_window_ms`, 240 a minute by default), the one page loads get.
  # It runs over the socket, where the HTTP rate limiter never looks, so
  # without this one page's session could make accounts as fast as a script
  # sends. Not the registration bucket (10 a minute): a class or a mobile
  # carrier shares one address, and that one also gates the login form.
  defp guest_rate_limit(ip) do
    case GamendWeb.LiveHelpers.check_rate_limit(ip || "unknown", :general) do
      :ok -> :ok
      {:error, _retry_after} -> {:error, :rate_limited}
    end
  end

  # A refused guest account, to the log, and the refusal back to the caller.
  # Callers carry on signed out (the visitor's save is not kept), so this line
  # is the only trace it leaves. The static render is expected and only
  # debug; a refusal the server meant (device accounts off, the per-IP limit)
  # is a warning; anything else (a hook refused it, the insert failed) an error.
  defp log_guest_refused(error, where) do
    reason = with {:error, reason} <- error, do: reason

    level =
      case reason do
        :not_connected -> :debug
        reason when reason in [:disabled, :rate_limited] -> :warning
        _other -> :error
      end

    Logger.log(level, "guest account not made on #{where}: #{inspect(reason)}")
    error
  end

  # A browser has no device id to send, so the server makes one up. `web:`
  # marks where the account came from.
  defp web_device_id,
    do: "web:" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  @doc false
  def encrypt_anonymous_session(token),
    do: Phoenix.Token.encrypt(GamendWeb.endpoint(), @anonymous_session_salt, token)

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      GamendWeb.endpoint().broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      # A reader back on their cookie signs nothing in, so no login path
      # records the day: this does (a cache read once it is recorded).
      Gamend.Analytics.record_activity(user.id)

      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    case get_session(conn, :user_token) do
      nil ->
        conn = fetch_cookies(conn, signed: [@remember_me_cookie])

        case conn.cookies[@remember_me_cookie] do
          nil ->
            nil

          token ->
            {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
        end

      token ->
        {token, conn}
    end
  end

  # A session token is reissued once it is half its validity old: an active
  # user is never logged out, and an idle one lasts the whole window from
  # their last visit. 7 days at the 14-day default.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at)

    if token_age >= div(session_seconds(), 2) do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user_id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token,
      sign: true,
      max_age: session_seconds(),
      same_site: "Lax"
    )
  end

  defp session_seconds, do: UserToken.session_validity_in_days() * 86_400

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      GamendWeb.endpoint().broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule GamendWeb.PageLive do
        use GamendWeb, :live_view

        on_mount {GamendWeb.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{GamendWeb.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    socket |> mount_current_scope(session) |> refuse_banned()
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Scope.user(socket.assigns.current_scope) do
      refuse_banned(socket)
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          gettext("Failed")
        )
        # This on_mount runs under the :require_authenticated_user live_session,
        # while the log-in LiveView lives under the :current_user live_session.
        # Forcing an external redirect avoids the client-side "unauthorized live_redirect"
        # warning and performs a clean full page navigation.
        |> Phoenix.LiveView.redirect(external: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    user = Scope.user(socket.assigns.current_scope)

    if user && user.is_admin do
      refuse_banned(socket)
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          gettext("Failed")
        )
        |> Phoenix.LiveView.redirect(external: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(
         Scope.user(socket.assigns.current_scope),
         -Accounts.sudo_mode_minutes()
       ) do
      refuse_banned(socket)
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          gettext("Failed")
        )
        # See :require_authenticated above for why this must be an external redirect.
        |> Phoenix.LiveView.redirect(external: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  # A banned account (`Gamend.Bans`) opens its settings, where it can delete
  # itself, and `/suspended`, which says why and until when; every other page
  # sends it there. Signed in, so the account is still the one it banned.
  @banned_views [GamendWeb.UserLive.Settings, GamendWeb.SuspendedLive]

  defp refuse_banned(socket) do
    with user_id when is_binary(user_id) <- Scope.user_id(socket.assigns.current_scope),
         false <- socket.view in @banned_views,
         true <- Gamend.Bans.banned?(:account, user_id) do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/suspended")}
    else
      _ -> {:cont, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn ->
        user_token = session["user_token"] || connect_session_token(socket)
        {user, _} = (user_token && Accounts.get_user_by_session_token(user_token)) || {nil, nil}

        Scope.for_user(user)
      end)
      |> assign_guest_ip(session)

    remember_reader(socket)
    record_reader_day(socket)

    # Attach hook to capture current_path for nav active state.
    # Only works for views mounted via live/3 in the router.
    try do
      Phoenix.LiveView.attach_hook(socket, :set_current_path, :handle_params, fn
        _params, uri, socket ->
          %URI{path: path} = URI.parse(uri)
          {:cont, Phoenix.Component.assign(socket, :current_path, path || "/")}
      end)
    rescue
      RuntimeError -> socket
    end
  end

  # Where `ensure_user/1` counts a signed-out visitor's new accounts. Read at
  # mount, the only time a LiveView has its session and connect info: the IP
  # the page was rendered for (`LiveHelpers.client_ip_session/1`, after
  # `RealIp`), else the socket's peer. Connected only: `ensure_user/1` never
  # makes an account on the static render.
  defp assign_guest_ip(socket, session) do
    if Scope.user(socket.assigns.current_scope) || not Phoenix.LiveView.connected?(socket) do
      socket
    else
      Phoenix.Component.assign_new(socket, :client_ip, fn ->
        GamendWeb.LiveHelpers.client_ip(socket, session)
      end)
    end
  end

  # A page mounts with the session it was rendered with, which predates a guest
  # account made on it (`ensure_user/1`). That account is in the cookie the
  # socket reconnected with (`anonymous_session.js`), so a signed-out page
  # session falls back to the socket's: without it the reconnect, and every
  # page navigated to after it, would mount the visitor signed out again.
  defp connect_session_token(socket) do
    if Phoenix.LiveView.connected?(socket) do
      case Phoenix.LiveView.get_connect_info(socket, :session) do
        %{"user_token" => token} when is_binary(token) -> token
        _ -> nil
      end
    end
  rescue
    # get_connect_info outside mount (a nested live_render) raises, and
    # `Phoenix.LiveViewTest` has no connect-time session to give.
    _error in [RuntimeError, FunctionClauseError] -> nil
  end

  # The reader's time zone (sent on the LiveView connect, `app.js`) and site
  # language (the locale this page is in), saved on their account the first
  # time they are seen and whenever they change: "their day" and "their
  # evening" for a daily and its reminder, and the language an email is
  # written in. A write happens only on a change, so a page load costs a map
  # lookup.
  # A socket can outlive the day its page was served on, and a live
  # navigation is not a request: the day is recorded on every connected mount
  # too (a cache read once it is).
  defp record_reader_day(socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         %Accounts.User{id: id} <- Scope.user(socket.assigns.current_scope) do
      Gamend.Analytics.record_activity(id)
    end

    :ok
  end

  defp remember_reader(socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         %Accounts.User{} = user <- Scope.user(socket.assigns.current_scope) do
      zone = (Phoenix.LiveView.get_connect_params(socket) || %{})["timezone"]
      locale = socket.assigns[:locale]
      prefs = Accounts.Preferences.get(user)

      changes =
        %{}
        |> then(fn acc ->
          if zone != prefs["timezone"] and not Accounts.TimeZone.manual?(user) and
               Accounts.TimeZone.valid?(zone),
             do: Map.put(acc, "timezone", zone),
             else: acc
        end)
        |> then(fn acc ->
          if is_binary(locale) and byte_size(locale) <= 16 and locale != prefs["locale"],
            do: Map.put(acc, "locale", locale),
            else: acc
        end)

      if changes != %{}, do: Accounts.Preferences.update(user, &Map.merge(&1, changes))
    end
  rescue
    # get_connect_params outside mount (a nested live_render) raises.
    RuntimeError -> :ok
  end

  @doc "Returns the path to redirect to after log in."
  # the user was already logged in, redirect to settings
  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{}}}) do
    ~p"/users/settings"
  end

  def signed_in_path(_), do: ~p"/"

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if Scope.user(conn.assigns.current_scope) do
      conn
    else
      conn
      |> put_flash(:error, gettext("Failed"))
      |> redirect(to: sign_in_redirect(conn, ~p"/users/log_in"))
      |> halt()
    end
  end

  @doc """
  Plug for routes a guest (an anonymous account, `Scope.anonymous?/1`) may not
  use either: a signed-out visitor goes to log in, a guest to register, which
  keeps what they did (`Accounts.upgrade_anonymous_user_and_deliver/4`). For a
  feature a host keeps for real accounts, where `require_authenticated_user`
  would let any guest through. With `web_registration` off the game registers
  its players, and a guest goes to log in too.
  """
  def require_registered_user(conn, _opts) do
    scope = conn.assigns.current_scope

    cond do
      Scope.user(scope) && not Scope.anonymous?(scope) ->
        conn

      Scope.user(scope) ->
        page =
          if GamendWeb.Features.enabled?(:web_registration),
            do: ~p"/users/register",
            else: ~p"/users/log_in"

        conn
        |> redirect(to: sign_in_redirect(conn, page))
        |> halt()

      true ->
        require_authenticated_user(conn, [])
    end
  end

  @doc """
  Plug for routes that require the user to be an admin.
  """
  def require_admin_user(conn, _opts) do
    user = Scope.user(conn.assigns.current_scope)

    if user && user.is_admin do
      conn
    else
      conn
      |> put_flash(:error, gettext("Failed"))
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  # The sign-in page, told to come back to the page a GET asked for
  # (`store_return_to/2`). The Referer would name the page before it.
  defp sign_in_redirect(%{method: "GET"} = conn, page),
    do: page <> "?" <> URI.encode_query(%{"return_to" => current_path(conn)})

  defp sign_in_redirect(_conn, page), do: page

  @doc """
  Plug (`:browser`): where a sign-in page (`/users/log_in`,
  `/users/register`, under a locale prefix too) sends the reader once signed
  in, kept as the session's `:user_return_to` for `log_in_user/3` (password,
  emailed link and provider alike): its `?return_to=<path>`, which a
  protected page's redirect sets, else the page the link was on (the
  `Referer`, this site only). With neither, the session keeps what it had,
  so a failed password, which comes back to this page, keeps it too.

  A sign-in page is therefore always loaded by a request: `GamendWeb.LiveNav`
  never takes a link to one over the socket.
  """
  def store_return_to(%{method: "GET", path_info: path_info} = conn, _opts) do
    with true <- sign_in_page?(path_info),
         path when is_binary(path) <-
           safe_return_to(conn.params["return_to"]) || referer_path(conn) do
      put_session(conn, :user_return_to, path)
    else
      _ -> conn
    end
  end

  def store_return_to(conn, _opts), do: conn

  # The path and query of the page a link on this site was on.
  defp referer_path(%{host: host} = conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: ^host, path: path, query: query} <- URI.parse(referer) do
      safe_return_to(if query, do: "#{path}?#{query}", else: path)
    else
      _ -> nil
    end
  end

  @doc """
  `path` when it names a page on this site to come back to: one leading
  `/`, never `//` or a backslash (both read as another host), no scheme or
  host, not a sign-in page itself. Else nil.
  """
  @spec safe_return_to(term()) :: String.t() | nil
  def safe_return_to(path) when is_binary(path) and byte_size(path) <= 2048 do
    with "/" <> rest <- path,
         false <- String.starts_with?(rest, "/"),
         false <- String.contains?(path, ["\\", "\r", "\n"]),
         %URI{scheme: nil, host: nil, path: page} when is_binary(page) <- URI.parse(path),
         false <- sign_in_page?(String.split(page, "/", trim: true)) do
      path
    else
      _ -> nil
    end
  end

  def safe_return_to(_path), do: nil

  @doc "Whether path segments name a sign-in page: log in or register, any locale prefix."
  @spec sign_in_page?([String.t()]) :: boolean()
  def sign_in_page?(path_info),
    do: Enum.take(path_info, -2) in [["users", "log_in"], ["users", "register"]]
end
