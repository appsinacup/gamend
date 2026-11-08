defmodule GamendWeb.BannedAccountRoutesTest do
  @moduledoc """
  A banned account on routes that need a signed-in user: a controller sends it
  to `/suspended`, and a LiveView route still decides for itself, so its
  settings page opens.
  """
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts.Scope
  alias Gamend.Bans
  alias GamendWeb.UserAuth

  # The first account registered is an admin, and an admin cannot be banned.
  setup do
    Gamend.AccountsFixtures.user_fixture()
    :ok
  end

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, ban} = Bans.ban(:account, user.id)
    %{ban: ban}
  end

  test "a controller route sends it to /suspended", %{conn: conn} do
    conn = post(conn, "/users/update_password", %{"user" => %{"password" => "irrelevant"}})

    assert redirected_to(conn) == "/suspended"
  end

  test "its settings page still opens", %{conn: conn} do
    assert conn |> get("/users/settings") |> html_response(200)
  end

  test "a route for registered accounts refuses it too", %{conn: conn, user: user} do
    conn =
      conn |> assign(:current_scope, Scope.for_user(user)) |> UserAuth.require_registered_user([])

    assert conn.halted
    assert redirected_to(conn) == "/suspended"
  end

  test "another account is let through", %{conn: conn} do
    other = Gamend.AccountsFixtures.user_fixture()

    conn =
      conn
      |> assign(:current_scope, Scope.for_user(other))
      |> UserAuth.require_authenticated_user([])

    refute conn.halted
  end

  test "a lifted ban lets it through", %{conn: conn, user: user, ban: ban} do
    {:ok, _lifted} = Bans.lift_ban(ban)

    conn =
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> UserAuth.require_authenticated_user([])

    refute conn.halted
  end
end
