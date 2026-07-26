defmodule GameServerWeb.AuthPagesRenderTest do
  @moduledoc """
  Permission + render tests for pages that require authentication
  (live_session :require_authenticated_user).
  Ensures unauthenticated users are redirected and authenticated users can render.
  """
  use GameServerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @auth_routes [
    {"/notifications", "Notifications"},
    {"/chat", "Chat"},
    {"/users/settings", "Settings"}
  ]

  describe "unauthenticated users are redirected to login" do
    for {path, _label} <- @auth_routes do
      test "GET #{path} redirects unauthenticated", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/users/log_in"}}} =
                 live(conn, unquote(path))
      end
    end
  end

  describe "authenticated users can render pages" do
    setup :register_and_log_in_user

    for {path, _label} <- @auth_routes do
      test "GET #{path} renders when authenticated", %{conn: conn} do
        {:ok, _view, _html} = live(conn, unquote(path))
      end
    end
  end
end
