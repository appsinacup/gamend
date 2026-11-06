defmodule GamendWeb.Api.V1.Admin.EconomyControllerTest do
  use GamendWeb.ConnCase, async: true

  alias Gamend.Accounts.User
  alias Gamend.Economy
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    admin = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    target = Gamend.AccountsFixtures.user_fixture()
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

    assert json_response(grant, 200)["data"]["balance"] == 100
    assert Economy.balance(target.id, "gold") == 100

    spend =
      post(conn, "/api/v1/admin/economy/spend", %{
        user_id: target.id,
        currency: "gold",
        amount: 30
      })

    assert json_response(spend, 200)["data"]["balance"] == 70
  end

  test "admin spend refuses to overspend", %{conn: conn, target: target} do
    conn =
      post(conn, "/api/v1/admin/economy/spend", %{user_id: target.id, currency: "gold", amount: 5})

    assert json_response(conn, 403)["error"] == "insufficient_funds"
  end

  describe "refusals" do
    test "a reason past the ledger's 64 characters is 422 validation_failed", %{
      conn: conn,
      target: target
    } do
      # Was a 500: the ledger's changeset matched no clause.
      conn =
        post(conn, "/api/v1/admin/economy/grant", %{
          user_id: target.id,
          currency: "gold",
          amount: 5,
          reason: String.duplicate("r", 65)
        })

      assert %{"error" => "validation_failed", "errors" => %{"reason" => [_ | _]}} =
               json_response(conn, 422)

      assert Economy.balance(target.id, "gold") == 0
    end

    test "a replayed idempotency_key answers the balance it left", %{conn: conn, target: target} do
      body = %{user_id: target.id, currency: "gold", amount: 5, idempotency_key: "grant-once"}

      assert json_response(post(conn, "/api/v1/admin/economy/grant", body), 200)["data"][
               "balance"
             ] == 5

      assert json_response(post(conn, "/api/v1/admin/economy/grant", body), 200)["data"][
               "balance"
             ] == 5
    end

    test "a currency or item name out of bounds is 400", %{conn: conn, target: target} do
      long = String.duplicate("c", 65)

      grant =
        post(conn, "/api/v1/admin/economy/grant", %{user_id: target.id, currency: long, amount: 1})

      assert json_response(grant, 400)["error"] == "invalid_currency"

      item =
        post(conn, "/api/v1/admin/economy/grant_item", %{
          user_id: target.id,
          item: long,
          quantity: 1
        })

      assert json_response(item, 400)["error"] == "invalid_item"
    end

    test "an unknown user is 404, a bad amount 400", %{conn: conn, target: target} do
      missing =
        post(conn, "/api/v1/admin/economy/grant", %{
          user_id: Ecto.UUID.generate(),
          currency: "gold",
          amount: 1
        })

      assert json_response(missing, 404)["error"] == "user_not_found"

      zero =
        post(conn, "/api/v1/admin/economy/spend", %{
          user_id: target.id,
          currency: "gold",
          amount: 0
        })

      assert json_response(zero, 400)["error"] == "invalid_amount"

      none =
        post(conn, "/api/v1/admin/economy/consume_item", %{
          user_id: target.id,
          item: "potion",
          quantity: 1
        })

      assert json_response(none, 403)["error"] == "insufficient_items"
    end
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

    assert json_response(g, 200)["data"]["quantity"] == 5

    c =
      post(conn, "/api/v1/admin/economy/consume_item", %{
        user_id: target.id,
        item: "potion",
        quantity: 2
      })

    assert json_response(c, 200)["data"]["quantity"] == 3

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

    assert json_response(conn, 403)["error"] == "insufficient_items"
  end
end
