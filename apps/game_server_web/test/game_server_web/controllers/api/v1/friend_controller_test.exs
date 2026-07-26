defmodule GameServerWeb.Api.V1.FriendControllerTest do
  use GameServerWeb.ConnCase

  alias GameServer.AccountsFixtures
  alias GameServer.Friends
  alias GameServer.Repo
  alias GameServerWeb.Auth.Guardian
  import Ecto.Query

  test "POST /api/v1/friends requires auth and creates a request", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    {:ok, token, _} = Guardian.encode_and_sign(a)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/friends", %{target_user_id: b.id})

    assert conn.status == 201
  end

  test "friend request -> accept -> friends list", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    # create request as a
    conn_a = conn |> put_req_header("authorization", "Bearer " <> token_a)
    conn_a = post(conn_a, "/api/v1/friends", %{target_user_id: b.id})
    assert conn_a.status == 201

    # refresh the friendship from DB
    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    # accept as b
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    conn_b = conn |> put_req_header("authorization", "Bearer " <> token_b)
    conn_b = post(conn_b, "/api/v1/friends/#{f.id}/accept")
    # accept returns 200 with empty object now
    assert conn_b.status == 200

    # a's friends list should include b and provide the friendship id
    conn_a2 = conn |> put_req_header("authorization", "Bearer " <> token_a)
    resp = get(conn_a2, "/api/v1/me/friends") |> json_response(200)
    assert Enum.any?(resp["data"], fn r -> r["id"] == b.id end)
    entry = Enum.find(resp["data"], fn r -> r["id"] == b.id end)
    assert is_binary(entry["friendship_id"])
    refute Map.has_key?(entry, "email")
    # verify the returned friendship_id can be used to delete the friendship
    del = delete(conn_a2, "/api/v1/friends/#{entry["friendship_id"]}")
    assert del.status == 200
  end

  test "requests endpoint returns incoming and outgoing", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = conn |> put_req_header("authorization", "Bearer " <> token_a)
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    # b should see incoming
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    conn_b = conn |> put_req_header("authorization", "Bearer " <> token_b)
    resp = get(conn_b, "/api/v1/me/friend_requests") |> json_response(200)

    # Expect exactly one incoming and zero outgoing requests
    assert [_] = resp["data"]["incoming"]
    assert [] = resp["data"]["outgoing"]

    incoming = hd(resp["data"]["incoming"])
    refute Map.has_key?(incoming["requester"], "email")
    refute Map.has_key?(incoming["target"], "email")
    assert incoming["requester"]["last_seen_at"] == "1970-01-01T00:00:00Z"
    assert incoming["target"]["last_seen_at"] == "1970-01-01T00:00:00Z"

    # meta total counts and pages should be present
    assert resp["meta"]["incoming"]["total_count"] == 1
    assert resp["meta"]["outgoing"]["total_count"] == 0
    assert resp["meta"]["incoming"]["total_pages"] == 1
    assert resp["meta"]["outgoing"]["total_pages"] == 0
  end

  test "DELETE cancels pending and deletes accepted", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = conn |> put_req_header("authorization", "Bearer " <> token_a)
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    # cancel as a
    conn_cancel = conn_a |> delete("/api/v1/friends/#{f.id}")
    # cancel/delete now returns 200 with empty object
    assert conn_cancel.status == 200

    # create again and accept
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    f2 =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    conn_b = conn |> put_req_header("authorization", "Bearer " <> token_b)
    post(conn_b, "/api/v1/friends/#{f2.id}/accept")

    # now either user can delete (remove friend)
    conn_del = conn_a |> delete("/api/v1/friends/#{f2.id}")
    # successful removal returns 200 with empty object
    assert conn_del.status == 200
  end

  test "unauthenticated actions are rejected", %{conn: conn} do
    # create should fail without auth
    conn = post(conn, "/api/v1/friends", %{target_user_id: 1})
    assert conn.status == 401

    # accept should also fail without auth
    conn2 = post(conn, "/api/v1/friends/1/accept")
    assert conn2.status == 401
  end

  test "cannot request self; duplicate request succeeds idempotently", %{conn: conn} do
    a = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = conn |> put_req_header("authorization", "Bearer " <> token_a)

    # self-request should return 400
    resp = post(conn_a, "/api/v1/friends", %{target_user_id: a.id})
    assert resp.status == 400

    # create a valid request to b then duplicate should succeed (idempotent)
    b = AccountsFixtures.user_fixture()
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})
    resp2 = post(conn_a, "/api/v1/friends", %{target_user_id: b.id})
    assert resp2.status == 201
  end

  test "reverse pending request is auto-accepted", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    # b sends request to a
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    conn_b = put_req_header(conn, "authorization", "Bearer " <> token_b)
    resp1 = post(conn_b, "/api/v1/friends", %{target_user_id: a.id})
    assert resp1.status == 201

    # now a sends request to b; create_request should accept existing reverse pending
    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = put_req_header(conn, "authorization", "Bearer " <> token_a)
    resp2 = post(conn_a, "/api/v1/friends", %{target_user_id: b.id})
    # should result in accepted (we accept in controller by returning 201 on create)
    assert resp2.status in [200, 201]

    # verify friendship is accepted
    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^b.id and fr.target_id == ^a.id
      )

    assert f.status == "accepted"
  end

  test "accept/reject/delete with invalid id return not_found", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = put_req_header(conn, "authorization", "Bearer " <> token_a)

    # accept nonexistent
    resp = post(conn_a, "/api/v1/friends/00000000-0000-0000-0000-000000000000/accept")
    assert resp.status == 404

    # reject nonexistent
    resp2 = post(conn_a, "/api/v1/friends/00000000-0000-0000-0000-000000000000/reject")
    assert resp2.status == 404

    # delete nonexistent
    resp3 = delete(conn_a, "/api/v1/friends/00000000-0000-0000-0000-000000000000")
    assert resp3.status == 404
  end

  test "cannot accept/reject/delete when not authorized", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()
    c = AccountsFixtures.user_fixture()

    # a -> b pending
    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = put_req_header(conn, "authorization", "Bearer " <> token_a)
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    # c trying to accept should get forbidden
    {:ok, token_c, _} = Guardian.encode_and_sign(c)
    conn_c = put_req_header(conn, "authorization", "Bearer " <> token_c)
    r = post(conn_c, "/api/v1/friends/#{f.id}/accept")
    assert r.status == 403

    # c trying to delete pending should be forbidden
    r2 = delete(conn_c, "/api/v1/friends/#{f.id}")
    assert r2.status == 403
  end

  test "target can block incoming request and blocked prevents new requests", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = put_req_header(conn, "authorization", "Bearer " <> token_a)
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    # b blocks the incoming request
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    conn_b = put_req_header(conn, "authorization", "Bearer " <> token_b)
    resp = post(conn_b, "/api/v1/friends/#{f.id}/block")
    # block returns 200 with empty object now
    assert resp.status == 200

    f2 = Repo.get!(GameServer.Friends.Friendship, f.id)
    assert f2.status == "blocked"

    # a should not be able to create again (blocked)
    resp2 = post(conn_a, "/api/v1/friends", %{target_user_id: b.id})
    assert resp2.status == 400
  end

  test "blocked list and unblock endpoint works", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = put_req_header(conn, "authorization", "Bearer " <> token_a)
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    # b blocks
    {:ok, token_b, _} = Guardian.encode_and_sign(b)
    conn_b = put_req_header(conn, "authorization", "Bearer " <> token_b)
    post(conn_b, "/api/v1/friends/#{f.id}/block")

    # b's blocked list should include the friendship
    resp = get(conn_b, "/api/v1/me/blocked") |> json_response(200)
    assert Enum.any?(resp["data"], fn r -> r["id"] == f.id end)
    blocked = Enum.find(resp["data"], fn r -> r["id"] == f.id end)
    refute Map.has_key?(blocked["requester"], "email")

    # meta should include total_count / total_pages
    assert resp["meta"]["total_count"] == 1
    assert resp["meta"]["total_pages"] == 1

    # unblock as b
    resp_unblock = post(conn_b, "/api/v1/friends/#{f.id}/unblock")
    # unblock returns 200 with empty object now
    assert resp_unblock.status == 200

    # friendship should be removed
    assert Repo.get(GameServer.Friends.Friendship, f.id) == nil

    # now a should be able to request again
    resp_new = post(conn_a, "/api/v1/friends", %{target_user_id: b.id})
    assert resp_new.status in [200, 201]
  end

  test "friends listing supports pagination", %{conn: conn} do
    # a will have 3 friends, ensure pagination returns 2 then 1
    a = AccountsFixtures.user_fixture()
    other = for _ <- 1..3, do: AccountsFixtures.user_fixture()

    # make friendships by having others send request -> accept
    Enum.each(other, fn u ->
      {:ok, _} = Friends.create_request(u.id, a.id)

      f =
        Repo.one(
          from fr in GameServer.Friends.Friendship,
            where: fr.requester_id == ^u.id and fr.target_id == ^a.id
        )

      {:ok, _} = Friends.accept_friend_request(f.id, %GameServer.Accounts.User{id: a.id})
    end)

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = conn |> put_req_header("authorization", "Bearer " <> token_a)

    # page 1, page_size 2
    resp1 = get(conn_a, "/api/v1/me/friends?page=1&page_size=2") |> json_response(200)
    assert length(resp1["data"]) == 2
    assert resp1["meta"]["page"] == 1
    assert resp1["meta"]["page_size"] == 2
    assert resp1["meta"]["has_more"] == true
    assert resp1["meta"]["total_count"] == 3
    assert resp1["meta"]["total_pages"] == 2

    # page 2 should contain remaining 1
    resp2 = get(conn_a, "/api/v1/me/friends?page=2&page_size=2") |> json_response(200)
    assert length(resp2["data"]) == 1
    assert resp2["meta"]["page"] == 2
    assert resp2["meta"]["has_more"] == false
    assert resp2["meta"]["total_count"] == 3
    assert resp2["meta"]["total_pages"] == 2
  end

  test "only target can block incoming request", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()
    c = AccountsFixtures.user_fixture()

    {:ok, token_a, _} = Guardian.encode_and_sign(a)
    conn_a = put_req_header(conn, "authorization", "Bearer " <> token_a)
    post(conn_a, "/api/v1/friends", %{target_user_id: b.id})

    f =
      Repo.one(
        from fr in GameServer.Friends.Friendship,
          where: fr.requester_id == ^a.id and fr.target_id == ^b.id
      )

    {:ok, token_c, _} = Guardian.encode_and_sign(c)
    conn_c = put_req_header(conn, "authorization", "Bearer " <> token_c)
    resp = post(conn_c, "/api/v1/friends/#{f.id}/block")
    assert resp.status == 403
  end

  describe "blacklisting a user by user id" do
    setup %{conn: conn} do
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(a)

      %{conn: put_req_header(conn, "authorization", "Bearer " <> token), a: a, b: b}
    end

    test "block then unblock a user with no prior friendship", %{conn: conn, a: a, b: b} do
      assert post(conn, "/api/v1/users/#{b.id}/block").status == 200
      assert Friends.blocked?(a.id, b.id)

      assert post(conn, "/api/v1/users/#{b.id}/unblock").status == 200
      refute Friends.blocked?(a.id, b.id)
    end

    test "blocking yourself is rejected", %{conn: conn, a: a} do
      resp = post(conn, "/api/v1/users/#{a.id}/block")

      assert resp.status == 400
      assert json_response(resp, 400)["error"] == "cannot_block_self"
    end

    test "unblocking a user who was never blocked is 404", %{conn: conn, b: b} do
      assert post(conn, "/api/v1/users/#{b.id}/unblock").status == 404
    end

    test "requires auth" do
      b = AccountsFixtures.user_fixture()

      assert build_conn() |> post("/api/v1/users/#{b.id}/block") |> Map.get(:status) == 401
    end

    test "GET /me/blacklist returns the blocked users themselves", %{conn: conn, b: b} do
      c = AccountsFixtures.user_fixture()

      assert post(conn, "/api/v1/users/#{b.id}/block").status == 200
      assert post(conn, "/api/v1/users/#{c.id}/block").status == 200

      resp = json_response(get(conn, "/api/v1/me/blacklist"), 200)

      assert Enum.sort(Enum.map(resp["data"], & &1["id"])) == Enum.sort([b.id, c.id])
      assert resp["meta"]["total_count"] == 2

      # unblocking drops it from the list
      post(conn, "/api/v1/users/#{b.id}/unblock")
      resp = json_response(get(conn, "/api/v1/me/blacklist"), 200)
      assert Enum.map(resp["data"], & &1["id"]) == [c.id]
    end

    test "GET /me/blacklist paginates", %{conn: conn} do
      for _ <- 1..3 do
        target = AccountsFixtures.user_fixture()
        post(conn, "/api/v1/users/#{target.id}/block")
      end

      resp = json_response(get(conn, "/api/v1/me/blacklist?page=1&page_size=2"), 200)

      assert length(resp["data"]) == 2
      assert resp["meta"]["total_count"] == 3
      assert resp["meta"]["has_more"] == true
    end

    test "GET /me/blacklist requires auth" do
      assert build_conn() |> get("/api/v1/me/blacklist") |> Map.get(:status) == 401
    end
  end
end
