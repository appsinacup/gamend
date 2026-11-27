defmodule GamendWeb.Api.V1.EconomyControllerTest do
  use GamendWeb.ConnCase, async: true

  alias Gamend.Economy
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token), user: user}
  end

  test "GET /me/wallet requires auth" do
    assert json_response(get(build_conn(), "/api/v1/me/wallet"), 401)
  end

  test "GET /me/wallet returns balances", %{conn: conn, user: user} do
    Economy.grant(user.id, "gold", 100)
    Economy.grant(user.id, "gems", 5)

    assert %{"data" => %{"gold" => 100, "gems" => 5}} =
             json_response(get(conn, "/api/v1/me/wallet"), 200)
  end

  test "GET /me/wallet/ledger returns the user's history", %{conn: conn, user: user} do
    Economy.grant(user.id, "gold", 100, reason: "reward")
    Economy.spend(user.id, "gold", 40, reason: "store")

    body = json_response(get(conn, "/api/v1/me/wallet/ledger"), 200)
    assert body["meta"]["total_count"] == 2
    assert [%{"delta" => -40} | _] = body["data"]
  end

  test "GET /me/inventory pages the stacks by item code, each with its metadata",
       %{conn: conn, user: user} do
    Gamend.Inventory.grant_item(user.id, "sword", 1)
    Gamend.Inventory.grant_item(user.id, "potion", 3)
    {:ok, _} = Gamend.Inventory.set_metadata(user.id, "sword", %{"enchant" => "fire"})
    # A stack with none left is not held.
    {:ok, _} = Gamend.Inventory.set_metadata(user.id, "empty", %{})

    body = json_response(get(conn, "/api/v1/me/inventory?page_size=1"), 200)

    assert [%{"item" => "potion", "quantity" => 3, "metadata" => %{}}] = body["data"]
    assert %{"total_count" => 2, "has_more" => true} = body["meta"]

    body = json_response(get(conn, "/api/v1/me/inventory?page=2&page_size=1"), 200)
    assert [%{"item" => "sword", "metadata" => %{"enchant" => "fire"}}] = body["data"]
  end
end
