defmodule GameServerWeb.Api.V1.Admin.EconomyControllerTest do
  use GameServerWeb.ConnCase, async: true

  alias GameServer.Accounts.User
  alias GameServer.Economy
  alias GameServer.Repo
  alias GameServerWeb.Auth.Guardian

  setup %{conn: conn} do
    admin = GameServer.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    target = GameServer.AccountsFixtures.user_fixture()
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token), target: target}
  end

  test "requires admin", %{target: target} do
    {:ok, token, _} = Guardian.encode_and_sign(target)
    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)
    assert json_response(get(conn, "/api/v1/admin/economy/wallets"), 403)
  end

  test "admin grants and spends against any user", %{conn: conn, target: target} do
    grant =
      post(conn, "/api/v1/admin/economy/grant", %{
        user_id: target.id,
        currency: "gold",
        amount: 100
      })

    assert json_response(grant, 200)["balance"] == 100
    assert Economy.balance(target.id, "gold") == 100

    spend =
      post(conn, "/api/v1/admin/economy/spend", %{
        user_id: target.id,
        currency: "gold",
        amount: 30
      })

    assert json_response(spend, 200)["balance"] == 70
  end

  test "admin spend refuses to overspend", %{conn: conn, target: target} do
    conn =
      post(conn, "/api/v1/admin/economy/spend", %{user_id: target.id, currency: "gold", amount: 5})

    assert json_response(conn, 400)["error"] == "insufficient_funds"
  end

  test "admin lists wallets and ledger", %{conn: conn, target: target} do
    Economy.grant(target.id, "gold", 100)

    wallets = json_response(get(conn, "/api/v1/admin/economy/wallets?user_id=#{target.id}"), 200)
    assert [%{"currency" => "gold", "balance" => 100}] = wallets["data"]

    ledger = json_response(get(conn, "/api/v1/admin/economy/ledger?user_id=#{target.id}"), 200)
    assert ledger["meta"]["total_count"] == 1
  end

  test "admin grants, consumes and lists items", %{conn: conn, target: target} do
    g =
      post(conn, "/api/v1/admin/economy/grant_item", %{
        user_id: target.id,
        item: "potion",
        quantity: 5
      })

    assert json_response(g, 200)["quantity"] == 5

    c =
      post(conn, "/api/v1/admin/economy/consume_item", %{
        user_id: target.id,
        item: "potion",
        quantity: 2
      })

    assert json_response(c, 200)["quantity"] == 3

    items = json_response(get(conn, "/api/v1/admin/economy/items?user_id=#{target.id}"), 200)
    assert [%{"item" => "potion", "quantity" => 3}] = items["data"]
  end

  test "admin consume_item refuses to overdraw", %{conn: conn, target: target} do
    conn =
      post(conn, "/api/v1/admin/economy/consume_item", %{
        user_id: target.id,
        item: "potion",
        quantity: 1
      })

    assert json_response(conn, 400)["error"] == "insufficient_items"
  end
end
