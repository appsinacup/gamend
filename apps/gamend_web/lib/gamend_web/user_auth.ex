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

  # The remember-me cookie lives exactly as long as the session token it holds:
  # both come from `auth.session_days` (`UserToken.session_validity_in_days/0`).
  @remember_me_cookie "_gamend_web_user_remember_me"

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
    {conn, user} = keep_scheduled_account(conn, user)

    conn = create_or_extend_session(conn, user, params)

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
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Scope.user(socket.assigns.current_scope) do
      {:cont, socket}
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
      {:cont, socket}
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
      {:cont, socket}
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

  defp mount_current_scope(socket, session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn ->
        {user, _} =
          if user_token = session["user_token"] do
            Accounts.get_user_by_session_token(user_token)
          end || {nil, nil}

        Scope.for_user(user)
      end)

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
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
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

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
