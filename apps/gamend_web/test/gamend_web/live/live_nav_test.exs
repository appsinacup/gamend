defmodule GamendWeb.LiveNavTest do
  @moduledoc """
  Public and signed-in pages share one `live_session`, so a move between them
  keeps the socket. A move runs no plugs, so the session itself refuses a
  signed-out reader (`GamendWeb.UserAuth`'s `:mount_route_scope`).
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GamendWeb.LiveNav

  defp route(path) do
    LiveNav.build(GamendWeb.Router).json
    |> Jason.decode!()
    |> Map.fetch!("routes")
    |> Enum.find(&(hd(&1) == path))
  end

  describe "the route table" do
    test "marks the signed-in pages, in the public pages' session" do
      assert ["/leaderboards", "current_user", _, false] = route("/leaderboards")
      assert ["/notifications", "current_user", _, true] = route("/notifications")
      assert ["/users/settings", "current_user", _, true] = route("/users/settings")
      assert ["/admin", "require_admin", _, false] = route("/admin")
    end

    test "gates every view of the signed-in routes, and none of the public ones" do
      %{signed_in_only: signed_in_only} = LiveNav.build(GamendWeb.Router)

      assert {GamendWeb.NotificationsLive, :index} in signed_in_only
      assert {GamendWeb.UserLive.Settings, :edit} in signed_in_only
      assert {GamendWeb.UserLive.Groups, :show} in signed_in_only
      refute {GamendWeb.LeaderboardsLive, :index} in signed_in_only
    end
  end

  describe "the page says who reads it" do
    test "signed out", %{conn: conn} do
      refute conn |> get("/leaderboards") |> html_response(200) =~ "data-signed-in"
    end

    test "signed in", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert conn |> get("/leaderboards") |> html_response(200) =~ "data-signed-in"
    end
  end

  describe "a move from a public page" do
    test "reaches a signed-in page over the socket", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {:ok, view, _html} = live(conn, "/leaderboards")

      assert {:ok, moved, html} = live_redirect(view, to: "/notifications")
      assert html =~ "Notifications"

      # And back.
      assert {:ok, _view, _html} = live_redirect(moved, to: "/leaderboards")
    end

    test "is refused to a signed-out reader", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/leaderboards")

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live_redirect(view, to: "/notifications")
    end

    test "cannot reach an admin page, another session", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {:ok, view, _html} = live(conn, "/leaderboards")

      assert {:error, {:redirect, _redirect}} = live_redirect(view, to: "/admin")
    end
  end
end
