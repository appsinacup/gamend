defmodule GamendWeb.LobbyControllerTest.VetoDisband do
  use Gamend.TestSupport.NoopHooks

  @impl true
  def before_lobby_delete(_lobby), do: {:error, :tournament_running}
end

defmodule GamendWeb.LobbyControllerTest.VetoCreate do
  use Gamend.TestSupport.NoopHooks

  @impl true
  def before_lobby_create(_attrs), do: {:error, "Rooms are closed tonight"}
end

defmodule GamendWeb.LobbyControllerTest.VetoStateAndUpdate do
  use Gamend.TestSupport.NoopHooks

  @impl true
  def before_lobby_state_change(_lobby, _from, _to), do: {:error, "Not between rounds"}

  @impl true
  def before_lobby_update(_lobby, _attrs), do: {:error, :frozen}
end

defmodule GamendWeb.Api.V1.LobbyControllerTest do
  use GamendWeb.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias GamendWeb.Auth.Guardian

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

  describe "a pinned WebRTC host writes to a lobby it is not a member of" do
    setup %{conn: conn} do
      server = AccountsFixtures.user_fixture()
      player = AccountsFixtures.user_fixture()

      {:ok, lobby} = Lobbies.create_lobby(%{title: "matchmade", hostless: true, is_hidden: true})
      assert {:ok, _} = Lobbies.join_lobby(player, lobby, %{bypass_hidden: true})

      {:ok, lobby} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: server.id)

      {:ok, token, _} = Guardian.encode_and_sign(server)

      %{
        conn: put_req_header(conn, "authorization", "Bearer " <> token),
        lobby: lobby,
        server: server,
        player: player
      }
    end

    test "PATCH /lobbies with an explicit lobby_id", %{conn: conn, lobby: lobby, server: server} do
      assert server.lobby_id == nil

      resp =
        conn
        |> patch("/api/v1/lobbies", %{"lobby_id" => lobby.id, "metadata" => %{"round" => 2}})
        |> json_response(200)
        |> Map.fetch!("data")

      assert resp["metadata"] == %{"round" => 2}
    end

    test "POST /lobbies/state with an explicit lobby_id", %{conn: conn, lobby: lobby} do
      resp =
        conn
        |> post("/api/v1/lobbies/state", %{"lobby_id" => lobby.id, "state" => "playing"})
        |> json_response(200)
        |> Map.fetch!("data")

      assert resp["state"] == "playing"
      assert Lobbies.get_lobby(lobby.id).state == "playing"
    end

    test "lobby_id never lands in the lobby's own attrs", %{conn: conn, lobby: lobby} do
      conn
      |> patch("/api/v1/lobbies", %{"lobby_id" => lobby.id, "title" => "Round 2"})
      |> json_response(200)

      reloaded = Lobbies.get_lobby(lobby.id)
      assert reloaded.title == "Round 2"
      assert reloaded.metadata == %{}
    end

    test "a seated player still cannot write to it", %{conn: conn, lobby: lobby, player: player} do
      {:ok, token, _} = Guardian.encode_and_sign(player)
      conn = put_req_header(conn, "authorization", "Bearer " <> token)

      assert json_response(post(conn, "/api/v1/lobbies/state", %{"state" => "playing"}), 403)

      assert json_response(
               patch(conn, "/api/v1/lobbies", %{"lobby_id" => lobby.id, "title" => "Hijacked"}),
               403
             )

      assert Lobbies.get_lobby(lobby.id).title == "matchmade"
    end

    test "a stranger gets 404 on a hidden lobby, not 403", %{conn: conn, lobby: lobby} do
      {:ok, token, _} = Guardian.encode_and_sign(AccountsFixtures.user_fixture())

      resp =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/v1/lobbies/state", %{"lobby_id" => lobby.id, "state" => "playing"})

      assert json_response(resp, 404)["error"] == "not_found"
    end

    test "a malformed lobby_id is a bad request", %{conn: conn} do
      resp = post(conn, "/api/v1/lobbies/state", %{"lobby_id" => "nope", "state" => "playing"})
      assert json_response(resp, 400)["error"] == "invalid_id"
    end

    test "omitting lobby_id while seated nowhere is still not_in_lobby", %{conn: conn} do
      resp = post(conn, "/api/v1/lobbies/state", %{"state" => "playing"})
      assert json_response(resp, 404)["error"] == "not_in_lobby"
    end
  end

  # The pattern that needs no new columns and no new response fields: the game
  # sets the headless server as `host_id` after creation, and it is the host in
  # the plain sense everywhere — including to a client, which compares `host_id`
  # as it always has.
  describe "a server set as host_id, seated in no lobby" do
    setup %{conn: conn} do
      server = AccountsFixtures.user_fixture()
      player = AccountsFixtures.user_fixture()

      {:ok, lobby} = Lobbies.create_lobby(%{title: "matchmade", hostless: true})
      assert {:ok, _} = Lobbies.join_lobby(player, lobby)

      {:ok, lobby} =
        Lobbies.update_lobby(lobby, %{"hostless" => false, "host_id" => server.id})

      {:ok, token, _} = Guardian.encode_and_sign(server)

      %{
        conn: put_req_header(conn, "authorization", "Bearer " <> token),
        lobby: lobby,
        server: server,
        player: player
      }
    end

    test "it moves the match state", %{conn: conn, lobby: lobby, server: server} do
      assert Gamend.Accounts.get_user(server.id).lobby_id == nil

      resp =
        conn
        |> post("/api/v1/lobbies/state", %{"lobby_id" => lobby.id, "state" => "playing"})
        |> json_response(200)
        |> Map.fetch!("data")

      assert resp["state"] == "playing"
    end

    test "it edits the lobby", %{conn: conn, lobby: lobby} do
      resp =
        conn
        |> patch("/api/v1/lobbies", %{"lobby_id" => lobby.id, "metadata" => %{"round" => 2}})
        |> json_response(200)
        |> Map.fetch!("data")

      assert resp["metadata"] == %{"round" => 2}
    end

    test "the client can tell who is in charge from host_id alone", %{
      conn: conn,
      lobby: lobby,
      server: server
    } do
      resp = conn |> get("/api/v1/lobbies/#{lobby.id}") |> json_response(200)
      assert resp["data"]["host_id"] == server.id
      refute resp["data"]["hostless"]
    end

    test "a seated player has no authority over it", %{conn: conn, lobby: lobby, player: player} do
      {:ok, token, _} = Guardian.encode_and_sign(player)

      resp =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/v1/lobbies/state", %{"state" => "playing"})

      assert json_response(resp, 403)["error"] == "not_host"
      assert Lobbies.get_lobby(lobby.id).state == "created"
    end
  end

  describe "GET /api/v1/lobbies/:id on a hidden lobby" do
    setup do
      host = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      outsider = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "hidden", host_id: host.id, is_hidden: true})
      assert {:ok, _} = Lobbies.join_lobby(member, lobby, %{bypass_hidden: true})

      %{lobby: lobby, host: host, member: member, outsider: outsider}
    end

    defp show_as(conn, user, lobby) do
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/v1/lobbies/#{lobby.id}")
    end

    test "a member can read it", %{conn: conn, lobby: lobby, member: member} do
      assert json_response(show_as(conn, member, lobby), 200)["data"]["id"] == lobby.id
    end

    test "the host can read it", %{conn: conn, lobby: lobby, host: host} do
      assert json_response(show_as(conn, host, lobby), 200)["data"]["id"] == lobby.id
    end

    # The case that started this: a hostless matchmaking lobby whose signaling
    # host is a headless game server, seated in no lobby of its own.
    test "the signaling host can read it even though it is not a member", %{conn: conn} do
      server = AccountsFixtures.user_fixture()

      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "matchmade", is_hidden: true, hostless: true})

      {:ok, lobby} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: server.id)

      assert lobby.webrtc_host_id == server.id

      assert server.lobby_id == nil
      assert json_response(show_as(conn, server, lobby), 200)["data"]["id"] == lobby.id
    end

    test "an outsider gets 404, not 403", %{conn: conn, lobby: lobby, outsider: outsider} do
      assert json_response(show_as(conn, outsider, lobby), 404)["error"] == "not_found"
    end
  end

  test "GET /api/v1/lobbies/:id rejects a malformed id as a bad request", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/v1/lobbies/not-a-uuid")

    assert json_response(conn, 400)["error"] == "invalid_id"
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

    resp = json_response(conn, 200)["data"]

    assert Enum.any?(resp["members"], fn m -> m["id"] == host.id end)
    assert Enum.all?(resp["members"], fn m -> not Map.has_key?(m, "email") end)
  end

  test "GET /api/v1/lobbies/:id keeps metadata for the people in the lobby, purchases for no one" do
    host = AccountsFixtures.user_fixture()
    outsider = AccountsFixtures.user_fixture()

    {:ok, _} =
      Gamend.Accounts.update_user_metadata(host.id, fn metadata ->
        Map.merge(metadata, %{
          "ship" => "brig",
          "payments" => %{"purchase_ids" => %{"p1" => true}}
        })
      end)

    {:ok, lobby} = Lobbies.create_lobby(%{title: "metadata-room", host_id: host.id})

    host_row = fn reader ->
      {:ok, token, _} = Guardian.encode_and_sign(reader)

      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/v1/lobbies/#{lobby.id}")
      |> json_response(200)
      |> get_in(["data", "members"])
      |> Enum.find(&(&1["id"] == host.id))
    end

    assert host_row.(host)["metadata"] == %{"ship" => "brig"}
    assert host_row.(outsider)["metadata"] == %{}
  end

  test "POST /api/v1/lobbies (hosted) requires auth and creates a lobby", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies", %{title: "api-room"})

    assert conn.status == 201
    lobby = json_response(conn, 201)["data"]
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

  defp create_as(conn, user, params) do
    {:ok, token, _} = Guardian.encode_and_sign(user)

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> post("/api/v1/lobbies", params)
  end

  defp party_of(leader, member) do
    {:ok, party} = Gamend.Parties.create_party(leader, %{max_size: 4})
    member |> Ecto.Changeset.change(%{party_id: party.id}) |> Gamend.Repo.update!()
    party
  end

  describe "POST /api/v1/lobbies failures" do
    test "a title another lobby has is fine: titles are not unique", %{conn: conn} do
      {:ok, _} = Lobbies.create_lobby(%{title: "Ranked 1v1", hostless: true})

      resp = conn |> create_as(AccountsFixtures.user_fixture(), %{title: "Ranked 1v1"})
      assert %{"title" => "Ranked 1v1"} = json_response(resp, 201)["data"]
    end

    test "invalid input answers 422 validation_failed, not 409", %{conn: conn} do
      resp = conn |> create_as(AccountsFixtures.user_fixture(), %{title: "room", max_users: 0})

      assert %{"error" => "validation_failed", "errors" => %{"max_users" => [_]}} =
               json_response(resp, 422)
    end

    test "a host already in a lobby answers 409 already_in_lobby", %{conn: conn} do
      host = AccountsFixtures.user_fixture()
      {:ok, _own} = Lobbies.create_lobby(%{title: "own-room", host_id: host.id})

      resp = conn |> create_as(host, %{title: "second-room"})
      assert json_response(resp, 409)["error"] == "already_in_lobby"
    end

    test "a game hook's refusal answers 403 rejected with its words", %{conn: conn} do
      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, GamendWeb.LobbyControllerTest.VetoCreate)
      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)

      resp = conn |> create_as(AccountsFixtures.user_fixture(), %{title: "room"})

      assert %{"error" => "rejected", "message" => "Rooms are closed tonight"} =
               json_response(resp, 403)
    end

    test "a party leader with a member offline answers 403 members_offline", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      party_of(leader, member)
      Gamend.Accounts.set_user_online(leader.id)

      resp = conn |> create_as(leader, %{title: "party-room"})
      assert json_response(resp, 403)["error"] == "members_offline"
    end

    test "a lobby smaller than the leader's party answers 403", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      party_of(leader, member)
      Enum.each([leader, member], &Gamend.Accounts.set_user_online(&1.id))

      resp = conn |> create_as(leader, %{title: "party-room", max_users: 1})
      assert json_response(resp, 403)["error"] == "lobby_too_small_for_party"
    end
  end

  test "POST /api/v1/lobbies/:id/join answers 409 when already in a lobby", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    {:ok, _own} = Lobbies.create_lobby(%{title: "own-room", host_id: host.id})
    {:ok, other} = Lobbies.create_lobby(%{title: "other-room", hostless: true})
    {:ok, token, _} = Guardian.encode_and_sign(host)

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{other.id}/join", %{})
      |> json_response(409)

    assert resp["error"] == "already_in_lobby"
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
    body = json_response(conn, 200)["data"]
    assert body["id"] == lobby.id

    reloaded = Gamend.Repo.get(User, other.id)
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

    body = json_response(conn, 200)["data"]
    assert body["id"] == lobby.id

    reloaded = Gamend.Repo.get(User, other.id)
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
    body = json_response(conn, 200)["data"]

    reloaded = Gamend.Repo.get(User, other.id)
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
    body2 = json_response(conn2, 200)["data"]
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
    body3 = json_response(conn3, 200)["data"]
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

    # The update targets the caller's own lobby: a non-host seated nowhere
    # has none (404 not_in_lobby); one seated but not hosting gets 403.
    assert json_response(conn1, 404)["error"] == "not_in_lobby"

    conn2 =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> patch("/api/v1/lobbies", %{title: "New Title"})

    assert json_response(conn2, 200)["data"]["title"] == "New Title"
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

    assert json_response(conn_ok, 200)["data"]["max_users"] == 6
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

    reloaded = Gamend.Repo.get(User, other.id)
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
    reloaded = Gamend.Repo.get(User, member2.id)
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
    reloaded = Gamend.Repo.get(User, host.id)
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

    reloaded = Gamend.Repo.get(User, other.id)
    assert is_nil(reloaded.lobby_id)
  end

  describe "a miss answers its code, never a crash" do
    setup %{conn: conn} do
      host = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "miss-room", host_id: host.id})
      {:ok, token, _} = Guardian.encode_and_sign(host)

      %{conn: put_req_header(conn, "authorization", "Bearer " <> token), host: host, lobby: lobby}
    end

    test "kicking a player who does not exist, or is not seated here, is not_found", %{
      conn: conn
    } do
      elsewhere = AccountsFixtures.user_fixture()

      for target <- [Ecto.UUID.generate(), "not-a-uuid", elsewhere.id] do
        conn = post(conn, "/api/v1/lobbies/kick", %{target_user_id: target})
        assert json_response(conn, 404)["error"] == "not_found"
      end
    end

    # The caller is read, then their lobby: a delete landing between the two
    # leaves a user naming a lobby that is gone (in production, a cached copy
    # does the same for up to the cache TTL).
    test "a lobby deleted under the caller is not_in_lobby", %{conn: conn, lobby: lobby} do
      other = AccountsFixtures.user_fixture()

      conn =
        delete_lobby_after_users_read(lobby, 2, fn ->
          post(conn, "/api/v1/lobbies/kick", %{target_user_id: other.id})
        end)

      assert json_response(conn, 404)["error"] == "not_in_lobby"
    end

    test "a hook vetoing a disband is rejected", %{conn: conn, lobby: lobby} do
      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, GamendWeb.LobbyControllerTest.VetoDisband)
      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)

      conn = post(conn, "/api/v1/lobbies/disband")
      assert json_response(conn, 403)["error"] == "rejected"
      assert Lobbies.get_lobby(lobby.id)
    end
  end

  test "POST /api/v1/lobbies/disband ends the lobby for everyone", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "disband-room", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_host, _} = Guardian.encode_and_sign(host)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_host)
      |> post("/api/v1/lobbies/disband")

    assert conn.status == 200
    assert is_nil(Lobbies.get_lobby(lobby.id))
    assert is_nil(Gamend.Repo.get(User, member.id).lobby_id)
  end

  # Ending it is the host's call; a member who wants out has leave, which takes
  # only them.
  test "POST /api/v1/lobbies/disband refuses a non-host", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "disband-guard", host_id: host.id})
    assert {:ok, _} = Lobbies.join_lobby(member, lobby)

    {:ok, token_member, _} = Guardian.encode_and_sign(member)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token_member)
      |> post("/api/v1/lobbies/disband")

    assert json_response(conn, 403)["error"] == "not_host"
    assert Lobbies.get_lobby(lobby.id)
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

    reloaded = Gamend.Repo.get(Gamend.Accounts.User, member.id)
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

    reloaded = Gamend.Repo.get(Gamend.Accounts.User, member.id)
    assert is_nil(reloaded.lobby_id)
  end

  # ---------------------------------------------------------------------------
  # Party members cannot individually create/join/quick_join lobbies
  # ---------------------------------------------------------------------------

  defp create_party_with_member do
    leader = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, party} = Gamend.Parties.create_party(leader)

    member =
      member
      |> Ecto.Changeset.change(%{party_id: party.id})
      |> Gamend.Repo.update!()

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

    Gamend.Accounts.set_user_online(leader.id)
    Gamend.Accounts.set_user_online(member.id)

    {:ok, token, _} = Guardian.encode_and_sign(leader)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies", %{title: "party-auto-lobby", max_users: 8})

    body = json_response(conn, 201)["data"]
    assert body["title"] == "party-auto-lobby"

    # Both leader and member should now be in the lobby
    reloaded_leader = Gamend.Repo.get(User, leader.id)
    reloaded_member = Gamend.Repo.get(User, member.id)
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

    Gamend.Accounts.set_user_online(leader.id)
    Gamend.Accounts.set_user_online(member.id)

    {:ok, lobby} = Lobbies.create_lobby(%{title: "target-lobby", max_users: 8})

    {:ok, token, _} = Guardian.encode_and_sign(leader)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join")

    body = json_response(conn, 200)["data"]
    assert body["id"] == lobby.id

    reloaded_leader = Gamend.Repo.get(User, leader.id)
    reloaded_member = Gamend.Repo.get(User, member.id)
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
    Gamend.Accounts.set_user_online(leader.id)
    Gamend.Accounts.set_user_online(member.id)

    # Reload leader to get the updated party_id
    leader = Gamend.Accounts.get_user(leader.id)
    assert leader.party_id == party.id

    {:ok, token, _} = Guardian.encode_and_sign(leader)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/quick_join", %{title: "party-quick"})

    resp = json_response(conn, 200)["data"]
    assert resp["id"]

    # Verify both members are now in the lobby
    updated_leader = Gamend.Accounts.get_user(leader.id)
    updated_member = Gamend.Accounts.get_user(member.id)
    assert updated_leader.lobby_id == resp["id"]
    assert updated_member.lobby_id == resp["id"]
  end

  test "POST join returns 403 blocked when a blacklisted player is seated", %{conn: conn} do
    host = AccountsFixtures.user_fixture()
    joiner = AccountsFixtures.user_fixture()
    {:ok, _} = Gamend.Friends.block_user(host, joiner.id)

    {:ok, lobby} = Lobbies.create_lobby(%{title: "blocked-room", host_id: host.id})

    {:ok, token, _} = Guardian.encode_and_sign(joiner)

    resp =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/v1/lobbies/#{lobby.id}/join")

    assert json_response(resp, 403)["error"] == "blocked"
    assert Gamend.Accounts.get_user(joiner.id).lobby_id == nil
  end

  # Each reason answers with the status `GamendWeb.ErrorStatus` gives it, the
  # same from every endpoint: a catch-all clause used to pick one per site.
  describe "the status follows the reason" do
    setup %{conn: conn} do
      host = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "reason-room", host_id: host.id})
      %{conn: conn, host: host, lobby: lobby}
    end

    defp as(conn, user) do
      {:ok, token, _} = Guardian.encode_and_sign(user)
      put_req_header(conn, "authorization", "Bearer " <> token)
    end

    defp veto_state_and_update do
      previous = Application.get_env(:gamend_core, :hooks_module)

      Application.put_env(
        :gamend_core,
        :hooks_module,
        GamendWeb.LobbyControllerTest.VetoStateAndUpdate
      )

      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)
    end

    test "a hook vetoing a state change is 403 rejected, not 422", %{conn: conn, host: host} do
      veto_state_and_update()

      resp = conn |> as(host) |> post("/api/v1/lobbies/state", %{"state" => "playing"})

      assert %{"error" => "rejected", "message" => "Not between rounds"} =
               json_response(resp, 403)
    end

    test "a hook vetoing an update is 403 rejected, not 422 unexpected_error", %{
      conn: conn,
      host: host
    } do
      veto_state_and_update()

      resp = conn |> as(host) |> patch("/api/v1/lobbies", %{title: "renamed"})
      assert %{"error" => "rejected", "message" => ":frozen"} = json_response(resp, 403)
    end

    test "joining a hidden lobby is 404 not_found, not 403 cannot_join", %{conn: conn} do
      host = AccountsFixtures.user_fixture()

      {:ok, hidden} =
        Lobbies.create_lobby(%{title: "secret-room", host_id: host.id, is_hidden: true})

      resp =
        conn |> as(AccountsFixtures.user_fixture()) |> post("/api/v1/lobbies/#{hidden.id}/join")

      assert json_response(resp, 404)["error"] == "not_found"
    end

    test "disbanding while seated nowhere is 404 not_in_lobby", %{conn: conn} do
      resp = conn |> as(AccountsFixtures.user_fixture()) |> post("/api/v1/lobbies/disband")
      assert json_response(resp, 404)["error"] == "not_in_lobby"
    end

    test "a party quick join with a member offline is 403 members_offline", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      party_of(leader, AccountsFixtures.user_fixture())
      Gamend.Accounts.set_user_online(leader.id)

      resp = conn |> as(leader) |> post("/api/v1/lobbies/quick_join", %{})
      assert json_response(resp, 403)["error"] == "members_offline"
    end
  end

  # Deletes `lobby` right after the `nth` read of the users table in this
  # process: the pipeline reads the caller once, the controller once more.
  defp delete_lobby_after_users_read(lobby, nth, fun) do
    test_pid = self()
    handler = {__MODULE__, :delete_lobby_after_users_read, System.unique_integer()}
    Process.put(:users_reads, 0)

    :telemetry.attach(
      handler,
      [:gamend, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == test_pid and meta[:source] == "users" and
             String.starts_with?(meta[:query], "SELECT") do
          reads = Process.put(:users_reads, Process.get(:users_reads) + 1) + 1

          if reads == nth,
            do: Gamend.Repo.delete_all(from l in Gamend.Lobbies.Lobby, where: l.id == ^lobby.id)
        end
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end
  end
end
