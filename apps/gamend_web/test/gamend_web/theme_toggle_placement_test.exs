defmodule GamendWeb.ThemeTogglePlacementTest do
  @moduledoc """
  Where the bar's theme toggle is: in the bar for a visitor, in the
  account's menu for a reader signed in (2026-10-30, user). The phone's
  menu keeps its own either way.
  """
  use GamendWeb.ConnCase, async: true

  # The desktop bar's links (`desktop_nav/1`), and the account's menu
  # (`user_menu/1`).
  @bar "ul.px-1.space-x-4 [data-phx-theme='dark']"
  @user_menu "details[data-navbar-dropdown] ul.w-56 [data-phx-theme='dark']"

  defp toggles(conn, selector) do
    conn
    |> get("/privacy")
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.count()
  end

  test "a visitor's bar has the toggle", %{conn: conn} do
    assert toggles(conn, @bar) == 1
    assert toggles(conn, @user_menu) == 0
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the toggle is in the account's menu, not the bar", %{conn: conn} do
      assert toggles(conn, @bar) == 0
      assert toggles(conn, @user_menu) == 1
    end
  end
end
