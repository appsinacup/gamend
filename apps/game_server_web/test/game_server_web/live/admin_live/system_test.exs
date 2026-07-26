defmodule GameServerWeb.AdminLive.SystemTest do
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  test "renders the retention card", %{conn: conn, admin: admin} do
    {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/admin/system")

    assert html =~ "Data Retention"
    assert html =~ "RETENTION_*"
    assert html =~ "never"
  end

  # The sweeper is not supervised under test, which is also what an instance
  # with retention disabled looks like: the button has to resolve, not hang.
  test "Run now reports a sweeper that is not running", %{conn: conn, admin: admin} do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/system")

    render_click(view, "prune_now")

    assert eventually(view, "Retention sweeper is not running.")
  end

  # The sweep runs in its own task, so the flash lands a beat after the click.
  defp eventually(view, text, attempts \\ 50) do
    cond do
      render(view) =~ text -> true
      attempts == 0 -> flunk("#{inspect(text)} never rendered")
      true -> Process.sleep(20) && eventually(view, text, attempts - 1)
    end
  end
end
