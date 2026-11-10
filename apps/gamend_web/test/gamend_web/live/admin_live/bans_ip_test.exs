defmodule GamendWeb.AdminLive.BansIpTest do
  @moduledoc """
  `/admin/bans` is the only place an IP is banned from the admin console.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Bans
  alias Gamend.Repo
  alias GamendWeb.Plugs.IpBan

  # TEST-NET-3: never a real client, so a ban here cannot shut out the suite.
  @ip "203.0.113.78"

  setup %{conn: conn} do
    Bans.Cache.init_table()
    on_exit(fn -> :ets.delete_all_objects(:bans) end)

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp ban(view, ip, duration) do
    render_submit(view, "ban", %{
      "kind" => "ip",
      "target" => ip,
      "duration" => duration,
      "reason" => "Scraping"
    })
  end

  test "an IP banned from the form is banned, listed, and lifted from its row", %{
    conn: conn,
    admin: admin
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/bans?kind=ip")

    ban(view, " #{@ip} ", "1h")

    assert IpBan.banned?(@ip)
    assert %{id: id, reason: "Scraping", banned_by: banned_by} = Bans.active(:ip, @ip)
    assert banned_by == admin.id
    lift = ~s([phx-click="lift"][phx-value-id="#{id}"])
    assert has_element?(view, lift)

    view |> element(lift) |> render_click()
    refute IpBan.banned?(@ip)
  end

  test "every duration is a ban", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/bans?kind=ip")

    for duration <- ~w(24h 7d 30d forever) do
      ban(view, @ip, duration)
      assert IpBan.banned?(@ip), "#{duration} did not ban"
      IpBan.unban(@ip)
    end
  end

  test "an empty IP is refused, nothing banned", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/bans?kind=ip")
    before = Bans.list_active(:ip)

    ban(view, "  ", "1h")

    assert Bans.list_active(:ip) == before
  end
end
