defmodule GamendWeb.AdminLive.GeoTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias GamendWeb.Plugs.GeoCountry

  setup do
    GeoCountry.init_table()
    GeoCountry.reset_stats()
    on_exit(&GeoCountry.reset_stats/0)

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  @browser "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0"

  defp request(agent) do
    :get
    |> Plug.Test.conn("/")
    |> Plug.Conn.put_req_header("user-agent", agent)
    |> GeoCountry.call([])
  end

  test "splits people from crawlers and names the crawlers", %{conn: conn, admin: admin} do
    request(@browser)
    request("Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)")
    request("Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)")

    # The page's own request goes through the plug too: a second person.
    {:ok, view, _html} =
      conn |> put_req_header("user-agent", @browser) |> log_in_user(admin) |> live(~p"/admin/geo")

    assert view |> element("#geo-people") |> render() =~ "50.0%"
    assert view |> element("#geo-crawlers") |> render() =~ "50.0%"
    assert view |> element("#geo-crawlers-table") |> render() =~ "Bingbot"
    assert has_element?(view, "#geo-crawler-kinds", "Search engines")

    # The country table follows the traffic switch.
    view |> element("#geo-traffic-people") |> render_click()
    assert has_element?(view, "#geo-traffic-people.btn-primary")
  end

  test "an empty window says so", %{conn: conn, admin: admin} do
    {:ok, view, _html} =
      conn |> put_req_header("user-agent", @browser) |> log_in_user(admin) |> live(~p"/admin/geo")

    assert view |> element("#geo-crawlers-table") |> render() =~ "No crawler traffic"
  end
end
