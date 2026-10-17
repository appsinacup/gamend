defmodule GamendWeb.AuthSuccessLiveTest do
  # The page a provider's sign-in lands on (`/auth/success`), which the
  # client SDK's window shows while it polls the session: done (and closing
  # itself), a conflict, an error, a session it cannot find, or one still
  # pending.
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.OAuthSessions

  defp status(view), do: :sys.get_state(view.pid).socket.assigns.session_data.status

  defp page(conn, session_id) do
    {:ok, view, _html} = live(conn, ~p"/auth/success?session_id=#{session_id}")
    view
  end

  test "a completed session says so and closes its window", %{conn: conn} do
    {:ok, _} =
      OAuthSessions.create_session("s-done", %{
        status: "completed",
        data: %{"message" => "Signed in"}
      })

    view = page(conn, "s-done")

    assert status(view) == "completed"
    assert has_element?(view, "#auto-close[phx-hook=AutoClose]")
  end

  test "a conflict and an error each say they failed, with no auto close", %{conn: conn} do
    for state <- ~w(conflict error) do
      {:ok, _} = OAuthSessions.create_session("s-#{state}", %{status: state, data: %{}})
      view = page(conn, "s-#{state}")
      assert status(view) == state
      refute has_element?(view, "#auto-close")
    end
  end

  test "a session still pending shows as loading", %{conn: conn} do
    {:ok, _} = OAuthSessions.create_session("s-pending", %{status: "pending", data: %{}})
    assert status(page(conn, "s-pending")) == "pending"
  end

  test "an id the server no longer has is taken as done; no id is not found", %{conn: conn} do
    assert status(page(conn, "s-gone")) == "completed"

    {:ok, view, _html} = live(conn, ~p"/auth/success")
    assert status(view) == "not_found"
    refute has_element?(view, "#auto-close")
  end
end
