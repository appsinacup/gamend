defmodule GamendWeb.AdminLive.RateLimitingTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Bans
  alias Gamend.Repo
  alias GamendWeb.Plugs.IpBan

  # TEST-NET-3: never a real client, so a ban here cannot shut out the suite.
  @ip "203.0.113.77"

  setup do
    Bans.Cache.init_table()
    on_exit(fn -> :ets.delete_all_objects(:bans) end)

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/rate_limiting")
    view
  end

  test "IP bans are placed on the bans page, which it links to", %{conn: conn, admin: admin} do
    view = page(conn, admin)

    assert has_element?(view, ~s(a[href="/admin/bans?kind=ip"]))
    refute has_element?(view, "#ban-ip-form")
  end

  test "the page refreshes its numbers on its timer", %{conn: conn, admin: admin} do
    view = page(conn, admin)

    IpBan.ban(@ip, expires_at: Bans.expires_after(:timer.hours(1)))
    send(view.pid, :refresh)

    assert has_element?(view, "#rate-limiting-ip-bans", "#{length(Bans.list_active(:ip))}")
    send(view.pid, :something_else)
    assert render(view)
  end
end
