defmodule GamendWeb.AdminLive.SystemTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  test "renders VM stats and every service", %{conn: conn, admin: admin} do
    {:ok, view, html} = conn |> log_in_user(admin) |> live(~p"/admin/system")

    assert html =~ "Memory (BEAM VM)"

    for service <- ~w(database cache cluster tls mail) do
      assert has_element?(view, "#service-#{service}"), "no #{service} card"
    end
  end

  test "each service links to the settings behind it", %{conn: conn, admin: admin} do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/system")

    assert has_element?(view, ~s(#service-database a[href="/admin/settings?group=db"]))
    assert has_element?(view, ~s(#service-mail a[href="/admin/settings?group=mail"]))
  end

  test "the test email button delivers to the admin and says so", %{conn: conn, admin: admin} do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/system")

    html = view |> element("#service-mail-test") |> render_click()

    assert html =~ "Test email sent to #{admin.email}"
    assert_receive {:email, email}
    assert Enum.any?(email.to, fn {_name, address} -> address == admin.email end)
  end
end
