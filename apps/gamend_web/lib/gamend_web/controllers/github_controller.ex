defmodule GamendWeb.GitHubController do
  @moduledoc """
  Connect a signed-in user to the installations of the server's GitHub App
  they may see (`Gamend.GitHub`), at `/github/*` (`gamend_github_routes/0`).

  Not a login: `/auth/github` is `GamendWeb.AuthController`'s and does that.
  This is the one round-trip after which `Gamend.GitHub.link_installations/3`
  can ask GitHub the only question that matters (which installations does
  this person have access to) with a token that proves the person asked.

  A page sends the person to `/github/connect?return_to=<path>` and gets them
  back there; without one, or when something fails, they land on the host's
  `config :gamend_web, :github_return_to` (`"/"` by default).

  The state is a `Gamend.OAuthSessions` row keyed on a random id, the way the
  login's browser flow does it, rather than a cookie: the callback is a
  top-level navigation from another origin and the session cookie is not
  guaranteed to ride along.
  """

  use GamendWeb, :controller

  alias Gamend.Accounts.Scope
  alias Gamend.GitHub
  alias Gamend.OAuthSessions

  require Logger
  require Gamend.OAuth.SessionStatus, as: SessionStatus

  @provider "github_app"

  @doc "Send the user to GitHub. `return_to` is where to land afterwards."
  def connect(conn, params) do
    if GitHub.configured?() do
      user = Scope.user(conn.assigns.current_scope)
      state = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

      {:ok, _session} =
        OAuthSessions.create_session(state, %{
          provider: @provider,
          status: SessionStatus.pending(),
          data: %{"user_id" => user.id, "return_to" => return_to(params)}
        })

      redirect(conn, external: GitHub.authorize_url(state, redirect_uri()))
    else
      conn
      |> put_flash(:error, gettext("GitHub is not set up on this server."))
      |> redirect(to: return_to(params) || fallback())
    end
  end

  @doc """
  GitHub sends the person back here with a code. The state has to be ours,
  pending, and issued to the user who is signed in now: a state minted for
  one account and redeemed in another would hand the second account the
  first one's installations.
  """
  def callback(conn, %{"code" => code, "state" => state}) when is_binary(state) do
    user = Scope.user(conn.assigns.current_scope)

    with %{data: data} <- OAuthSessions.get_pending_session(state, @provider) || {:error, :state},
         _ = OAuthSessions.update_session(state, %{status: SessionStatus.completed()}),
         true <- data["user_id"] == user.id || {:error, :state},
         {:ok, installations} <- GitHub.link_installations(user, code, redirect_uri()) do
      conn
      |> put_flash(:info, connected_message(installations))
      |> redirect(to: data["return_to"] || fallback())
    else
      {:error, :state} ->
        conn
        |> put_flash(:error, gettext("That GitHub sign-in has expired. Try again."))
        |> redirect(to: fallback())

      {:error, reason} ->
        Logger.warning("github: connect failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, gettext("GitHub did not accept the sign-in. Try again."))
        |> redirect(to: fallback())
    end
  end

  # GitHub answers a refusal with `error` and no code; a bare visit has neither.
  def callback(conn, _params) do
    conn
    |> put_flash(:error, gettext("GitHub did not complete the sign-in."))
    |> redirect(to: fallback())
  end

  @doc """
  The App's setup URL. GitHub lands here after an install with
  `installation_id` and `setup_action`, and both are ignored on purpose: the
  person is sent round the connect flow, and GitHub's own answer about what
  they may see is what gets recorded.
  """
  def setup(conn, _params) do
    redirect(conn, to: "/github/connect")
  end

  @doc "Where GitHub sends the person back. Registered on the App as a callback URL."
  @spec redirect_uri() :: String.t()
  def redirect_uri, do: GamendWeb.endpoint().url() <> "/github/callback"

  defp connected_message([]),
    do: gettext("GitHub is connected, but the App is not installed anywhere you can see.")

  defp connected_message(installations) do
    gettext("GitHub is connected: %{count} installation(s).", count: length(installations))
  end

  defp fallback, do: Application.get_env(:gamend_web, :github_return_to, "/")

  # Only a path on this site is followed back to. Anything else, a full URL
  # or a protocol-relative one, is somebody trying to use the callback as an
  # open redirect.
  defp return_to(%{"return_to" => "//" <> _}), do: nil
  defp return_to(%{"return_to" => "/" <> _ = path}), do: path
  defp return_to(_params), do: nil
end
