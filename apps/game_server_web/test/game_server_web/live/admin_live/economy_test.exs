defmodule GameServerWeb.AdminLive.EconomyTest do
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Economy
  alias GameServer.Inventory
  alias GameServer.Repo

  defp admin_conn(conn) do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    log_in_user(conn, admin)
  end

  test "economy admin deep-links to a user's wallet/items via ?user_id=", %{conn: conn} do
    conn = admin_conn(conn)
    u1 = AccountsFixtures.user_fixture()
    u2 = AccountsFixtures.user_fixture()

    {:ok, _} = Economy.grant(u1.id, "gold", 111, reason: "t")
    {:ok, _} = Economy.grant(u2.id, "gold", 222, reason: "t")
    {:ok, _} = Inventory.grant_item(u1.id, "mine_potion", 7)
    {:ok, _} = Inventory.grant_item(u2.id, "their_sword", 9)

    {:ok, _lv, html} = live(conn, ~p"/admin/economy?user_id=#{u1.id}")

    # Filtered to u1: their balance and item show, the other user's do not.
    # Balances are matched tag-bounded (>NNN<) so they can't collide with the
    # digits in a rendered username (fixtures auto-generate "word-NNNN" names).
    assert html =~ ">111<"
    refute html =~ ">222<"
    assert html =~ "mine_potion"
    refute html =~ "their_sword"
  end
end
