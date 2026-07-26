defmodule GameServerWeb.Api.V1.LobbyControllerTest do
  use GameServerWeb.ConnCase

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServerWeb.Auth.Guardian

  setup do
    {:ok, %{}}
  end

  test "GET /api/v1/lobbies lists lobbies but hides hidden ones", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    {:ok, lobby1} = Lobbies.create_lobby(%{title: "visible-room", host_id: host.id})

    {:ok, hostless_visible} =
      Lobbies.create_lobby(%{title: "visible-hostless-room", hostless: true})

    {:ok, hidden} =
      Lobbies.create_lobby(%{title: "hidden-room", hostless: true, is_hidden: true})

    conn = get(conn, "/api/v1/lobbies")
    resp = json_response(conn, 200)
    lobbies = resp["data"]
    assert Enum.any?(lobbies, fn l -> l["id"] == lobby1.id end)
    assert Enum.any?(lobbies, fn l -> l["id"] == hostless_visible.id and l["host_id"] == "" end)
    # display name fields are present in serialized lobbies
    assert Enum.all?(lobbies, fn l -> Map.has_key?(l, "host_name") end)
    # ensure serializer includes is_passworded flag
    assert Enum.any?(lobbies, fn l -> l["id"] == lobby1.id and l["is_passworded"] == false end)
    refute Enum.any?(lobbies, fn l -> l["id"] == hidden.id end)
    # meta should include totals
    assert resp["meta"]["total_count"] == 2
    assert resp["meta"]["total_pages"] == 1
  end

  test "GET /api/v1/lobbies filters by is_passworded and is_locked and max_users range", %{
    conn: conn
  } do
    host = AccountsFixtures.user_fixture()

    # create both locked/unlocked and passworded/unpassworded lobbies
    phash = Bcrypt.hash_pwd_salt("pw")

    {:ok, p_lobby} =
      Lobbies.create_lobby(%{
        title: "pw-room",
        host_id: host.id,
        password_hash: phash,
        max_users: 5
      })

    {:ok, locked} =
      Lobbies.create_lobby(%{
        title: "locked-room",
        host_id: AccountsFixtures.user_fixture().id,
        is_locked: true,
        max_users: 2
      })

    {:ok, open_small} =
      Lobbies.create_lobby(%{
        title: "open-small",
        host_id: AccountsFixtures.user_fixture().id,
        max_users: 2
      })

    {:ok, open_big} =
      Lobbies.create_lobby(%{
        title: "open-big",
        host_id: AccountsFixtures.user_fixture().id,
        max_users: 10
      })

    conn1 = get(conn, "/api/v1/lobbies", %{is_passworded: "true"})
    resp1 = json_response(conn1, 200)
    assert Enum.any?(resp1["data"], fn l -> l["id"] == p_lobby.id end)

    conn2 = get(conn, "/api/v1/lobbies", %{is_locked: "true"})
    resp2 = json_response(conn2, 200)
    assert Enum.any?(resp2["data"], fn l -> l["id"] == locked.id end)

    conn3 = get(conn, "/api/v1/lobbies", %{min_users: 3, max_users: 20})
    resp3 = json_response(conn3, 200)
    assert Enum.any?(resp3["data"], fn l -> l["id"] == open_big.id end)
    refute Enum.any?(resp3["data"], fn l -> l["id"] == open_small.id end)
  end

  test "GET /api/v1/lobbies/:id omits member emails", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "public-members", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)
    {:ok, token, _} = Guardian.encode_and_sign(host)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/v1/lobbies/#{lobby.id}")

    resp = json_response(conn, 200)

    assert Enum.any?(resp["members"], fn m -> m["id"] == host.id end)
    assert Enum.all?(resp["members"], fn m -> not Map.has_key?(m, "email") end)
  end

  test "POST /api/v1/lobbies (hosted) requires auth and creates a lobby", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies", %{title: "api-room"})

    assert conn.status == 201
    lobby = json_response(conn, 201)
    assert lobby["host_id"] == user.id
    assert Map.has_key?(lobby, "host_name")
    # 'name' (slug) is omitted from API responses - the unique id is used instead
    refute Map.has_key?(lobby, "name")

    # 'name' intentionally omitted
  end

  test "POST /api/v1/lobbies hostless creation removed from public API returns unauthorized", %{
    conn: conn
  } do
    conn = post(conn, "/api/v1/lobbies", %{title: "service-room", hostless: true})
    assert conn.status == 401
  end

  test "POST /api/v1/lobbies/:id/join requires auth and manages lobby membership", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "api-join-room", host_id: host.id, max_users: 2})

    {:ok, token, _} = Guardian.encode_and_sign(other)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join", %{})

    # join now returns the lobby representation
    assert conn.status == 200
    body = json_response(conn, 200)
    assert body["id"] == lobby.id

    reloaded = GameServer.Repo.get(User, other.id)
    assert reloaded.lobby_id == lobby.id
  end

  test "POST /api/v1/lobbies/quick_join joins an existing matching lobby (no password)", %{
    conn: conn
  } do
    host = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()

    # create a non-passworded lobby that will match metadata
    {:ok, lobby} =
      Lobbies.create_lobby(%{
        title: "quick-api-room",
        host_id: host.id,
        max_users: 4,
        metadata: %{mode: "capture", region: "EU"}
      })

    {:ok, token, _} = Guardian.encode_and_sign(other)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/quick_join", %{max_users: 4, metadata: %{mode: "cap"}})

    assert conn.status == 200

    body = json_response(conn, 200)
    assert body["id"] == lobby.id

    reloaded = GameServer.Repo.get(User, other.id)
    assert reloaded.lobby_id == lobby.id
  end

  test "POST /api/v1/lobbies/quick_join creates a new lobby when none match", %{conn: conn} do
    other = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(other)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/quick_join", %{
        title: "api-quick-new",
        max_users: 5,
        metadata: %{mode: "coop"}
      })

    assert conn.status == 200
    body = json_response(conn, 200)

    reloaded = GameServer.Repo.get(User, other.id)
    assert reloaded.lobby_id == body["id"]
    # and it should also accept metadata supplied as a JSON string and decode it
    json_metadata = Jason.encode!(%{mode: "cap"})

    other2 = AccountsFixtures.user_fixture()
    {:ok, token2, _} = Guardian.encode_and_sign(other2)

    conn2 =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token2)
      |> post("/api/v1/lobbies/quick_join", %{max_users: 4, metadata: json_metadata})

    assert conn2.status == 200
    body2 = json_response(conn2, 200)
    assert Map.get(body2, "metadata")["mode"] == "cap"
    # response should contain decoded metadata
    assert body2["max_users"] == 4
  end

  test "POST /api/v1/lobbies/:id/join with password requires correct password", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    pw = "s3cret"
    phash = Bcrypt.hash_pwd_salt(pw)

    {:ok, lobby} =
      Lobbies.create_lobby(%{title: "pw-room-api", host_id: host.id, password_hash: phash})

    {:ok, token, _} = Guardian.encode_and_sign(other)

    conn1 =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join", %{})

    assert conn1.status == 403

    conn2 =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join", %{password: "wrong"})

    assert conn2.status == 403

    conn3 =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join", %{password: pw})

    # join should return the lobby representation now
    assert conn3.status == 200
    body3 = json_response(conn3, 200)
    assert body3["id"] == lobby.id
  end

  test "PATCH /api/v1/lobbies/:id update allowed for host only", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {:ok, _lobby} = Lobbies.create_lobby(%{title: "update-room", host_id: host.id})

    {:ok, token_host, _} = Guardian.encode_and_sign(host)
    {:ok, token_other, _} = Guardian.encode_and_sign(other)

    conn1 =
      conn
      |> put_req_header("authorization", "Bearer " <> token_other)
      |> patch("/api/v1/lobbies", %{title: "bad"})

    # After switching to using the authenticated user's lobby, a non-host
    # who isn't in the lobby will get 400 (not_in_lobby) - if the user
    # is in the lobby but not host they'd get 403. Accept either.
    assert conn1.status in [400, 403, 422]

    conn2 =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> patch("/api/v1/lobbies", %{title: "New Title"})

    assert json_response(conn2, 200)["title"] == "New Title"
  end

  test "PATCH /api/v1/lobbies is forbidden for a non-host member", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "member-patch-room", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> patch("/api/v1/lobbies", %{title: "Hijacked"})

    assert json_response(conn, 403)["error"] == "not_host"
    assert Lobbies.get_lobby(lobby.id).title == "member-patch-room"
  end

  test "PATCH /api/v1/lobbies is forbidden for every member of a hostless lobby", %{conn: conn} do
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "hostless-patch-room", hostless: true})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> patch("/api/v1/lobbies", %{title: "Hijacked", metadata: %{"score" => 999}})

    assert json_response(conn, 403)["error"] == "not_host"

    reloaded = Lobbies.get_lobby(lobby.id)
    assert reloaded.title == "hostless-patch-room"
    assert reloaded.metadata == %{}
  end

  test "PATCH /api/v1/lobbies/:id cannot shrink max_users below current membership", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member1 = AccountsFixtures.user_fixture()
    member2 = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "resize-room", host_id: host.id, max_users: 3})

    # two members join making total 3 (host + 2)
    assert {:ok, _} = Lobbies.join_lobby(member1, lobby)
    assert {:ok, _} = Lobbies.join_lobby(member2, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)

    # attempt to shrink to 2 should fail
    conn_fail =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> patch("/api/v1/lobbies", %{max_users: 2})

    assert conn_fail.status == 422
    assert json_response(conn_fail, 422)["error"] == "too_small"

    # increasing works
    conn_ok =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> patch("/api/v1/lobbies", %{max_users: 6})

    assert json_response(conn_ok, 200)["max_users"] == 6
  end

  test "POST /api/v1/lobbies/:id/kick allowed for host", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "kick-api-room", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(other, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> post("/api/v1/lobbies/kick", %{target_user_id: other.id})

    # kick returns 200 with empty object now
    assert conn.status == 200

    reloaded = GameServer.Repo.get(User, other.id)
    assert is_nil(reloaded.lobby_id)
  end

  test "POST /api/v1/lobbies/:id/kick forbidden for non-host", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member1 = AccountsFixtures.user_fixture()
    member2 = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "kick-forbidden-room", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member1, lobby)
    assert {:ok, _} = Lobbies.join_lobby(member2, lobby)

    # member1 tries to kick member2 - should be forbidden
    {:ok, token_member1, _} = Guardian.encode_and_sign(member1)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_member1)
      |> post("/api/v1/lobbies/kick", %{target_user_id: member2.id})

    assert conn.status == 403
    assert json_response(conn, 403)["error"] == "not_host"

    # member2 should still be in the lobby
    reloaded = GameServer.Repo.get(User, member2.id)
    assert reloaded.lobby_id == lobby.id
  end

  test "POST /api/v1/lobbies/:id/kick host cannot kick self", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "self-kick-room", host_id: host.id})

    {:ok, token_host, _} = Guardian.encode_and_sign(host)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> post("/api/v1/lobbies/kick", %{target_user_id: host.id})

    assert conn.status == 403
    assert json_response(conn, 403)["error"] == "cannot_kick_self"

    # host should still be in the lobby
    reloaded = GameServer.Repo.get(User, host.id)
    assert reloaded.lobby_id == lobby.id
  end

  test "POST /api/v1/lobbies/:id/kick uses authenticated user's lobby when path id mismatches", %{
    conn: conn
  } do
    host = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "kick-mismatch-room", host_id: host.id})

    # create a different lobby to use as mismatched path id
    other_host = AccountsFixtures.user_fixture()
    {:ok, _other_lobby} = Lobbies.create_lobby(%{title: "other-room", host_id: other_host.id})

    assert {:ok, _} = Lobbies.join_lobby(other, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> post("/api/v1/lobbies/kick", %{target_user_id: other.id})

    # kick returns 200 with empty object now and uses host's lobby, not path id
    assert conn.status == 200

    reloaded = GameServer.Repo.get(User, other.id)
    assert is_nil(reloaded.lobby_id)
  end

  test "POST /api/v1/lobbies/:id/leave removes user from lobby", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "leave-room", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_member, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_member)
      |> post("/api/v1/lobbies/leave")

    # leave now returns 200 with empty object
    assert conn.status == 200

    reloaded = GameServer.Repo.get(GameServer.Accounts.User, member.id)
    assert is_nil(reloaded.lobby_id)
  end

  test "POST /api/v1/lobbies/:id/leave ignores path id and removes authenticated user", %{
    conn: conn
  } do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "leave-mismatch-room", host_id: host.id})

    {:ok, _other_lobby} =
      Lobbies.create_lobby(%{
        title: "other-leave-room",
        host_id: AccountsFixtures.user_fixture().id
      })

    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_member, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_member)
      |> post("/api/v1/lobbies/leave")

    assert conn.status == 200

    reloaded = GameServer.Repo.get(GameServer.Accounts.User, member.id)
    assert is_nil(reloaded.lobby_id)
  end

  # ---------------------------------------------------------------------------
  # Party members cannot individually create/join/quick_join lobbies
  # ---------------------------------------------------------------------------

  defp create_party_with_member do
    leader = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, party} = GameServer.Parties.create_party(leader)

    member =
      member
      |> Ecto.Changeset.change(%{party_id: party.id})
      |> GameServer.Repo.update!()

    {leader, member, party}
  end

  test "POST /api/v1/lobbies returns in_party when non-leader party member tries to create", %{
    conn: conn
  } do
    {_leader, member, _party} = create_party_with_member()

    {:ok, token, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies", %{title: "solo-lobby"})

    assert json_response(conn, 403)["error"] == "in_party"
  end

  test "POST /api/v1/lobbies as party leader auto-creates lobby for entire party", %{
    conn: conn
  } do
    {leader, member, _party} = create_party_with_member()

    GameServer.Accounts.set_user_online(leader.id)
    GameServer.Accounts.set_user_online(member.id)

    {:ok, token, _} = Guardian.encode_and_sign(leader)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies", %{title: "party-auto-lobby", max_users: 8})

    body = json_response(conn, 201)
    assert body["title"] == "party-auto-lobby"

    # Both leader and member should now be in the lobby
    reloaded_leader = GameServer.Repo.get(User, leader.id)
    reloaded_member = GameServer.Repo.get(User, member.id)
    assert reloaded_leader.lobby_id == body["id"]
    assert reloaded_member.lobby_id == body["id"]
  end

  test "POST /api/v1/lobbies/:id/join returns in_party for non-leader party member", %{
    conn: conn
  } do
    {_leader, member, _party} = create_party_with_member()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "target-lobby", max_users: 8})

    {:ok, token, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join")

    assert json_response(conn, 403)["error"] == "in_party"
  end

  test "POST /api/v1/lobbies/:id/join as party leader auto-joins lobby for entire party", %{
    conn: conn
  } do
    {leader, member, _party} = create_party_with_member()

    GameServer.Accounts.set_user_online(leader.id)
    GameServer.Accounts.set_user_online(member.id)

    {:ok, lobby} = Lobbies.create_lobby(%{title: "target-lobby", max_users: 8})

    {:ok, token, _} = Guardian.encode_and_sign(leader)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join")

    body = json_response(conn, 200)
    assert body["id"] == lobby.id

    reloaded_leader = GameServer.Repo.get(User, leader.id)
    reloaded_member = GameServer.Repo.get(User, member.id)
    assert reloaded_leader.lobby_id == lobby.id
    assert reloaded_member.lobby_id == lobby.id
  end

  test "POST /api/v1/lobbies/quick_join returns not_leader for non-leader party member", %{
    conn: conn
  } do
    {_leader, member, _party} = create_party_with_member()

    {:ok, token, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/quick_join", %{title: "quick"})

    assert json_response(conn, 403)["error"] == "not_leader"
  end

  test "POST /api/v1/lobbies/quick_join with party leader joins whole party", %{conn: conn} do
    {leader, member, party} = create_party_with_member()

    # Mark both members as online so the online check passes
    GameServer.Accounts.set_user_online(leader.id)
    GameServer.Accounts.set_user_online(member.id)

    # Reload leader to get the updated party_id
    leader = GameServer.Accounts.get_user(leader.id)
    assert leader.party_id == party.id

    {:ok, token, _} = Guardian.encode_and_sign(leader)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/quick_join", %{title: "party-quick"})

    resp = json_response(conn, 200)
    assert resp["id"]

    # Verify both members are now in the lobby
    updated_leader = GameServer.Accounts.get_user(leader.id)
    updated_member = GameServer.Accounts.get_user(member.id)
    assert updated_leader.lobby_id == resp["id"]
    assert updated_member.lobby_id == resp["id"]
  end

  test "POST join returns 403 blocked when a blacklisted player is seated", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    joiner = AccountsFixtures.user_fixture()
    {:ok, _} = GameServer.Friends.block_user(host, joiner.id)

    {:ok, lobby} = Lobbies.create_lobby(%{title: "blocked-room", host_id: host.id})

    {:ok, token, _} = Guardian.encode_and_sign(joiner)

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join")

    assert json_response(resp, 403)["error"] == "blocked"
    assert GameServer.Accounts.get_user(joiner.id).lobby_id == nil
  end
end
