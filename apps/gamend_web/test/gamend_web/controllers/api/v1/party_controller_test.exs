defmodule GamendWeb.PartyControllerTest.VetoAll do
  use Gamend.TestSupport.NoopHooks

  @impl true
  def before_party_update(_party, _attrs), do: {:error, "Settings are locked"}

  @impl true
  def before_party_join(_user, _party), do: {:error, :crew_only}
end

defmodule GamendWeb.Api.V1.PartyControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias GamendWeb.Auth.Guardian

  setup do
    {:ok, %{}}
  end

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp add_member_to_party(user, party) do
    user
    |> Ecto.Changeset.change(%{party_id: party.id})
    |> Gamend.Repo.update!()
  end

  defp set_all_online(users) do
    Enum.each(users, &Accounts.set_user_online(&1.id))
  end

  describe "POST /api/v1/parties" do
    test "creates a party", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> auth_conn(user)
        |> post("/api/v1/parties", %{max_size: 4})

      assert conn.status == 201
      body = json_response(conn, 201)["data"]
      assert body["leader_id"] == user.id
      assert Map.has_key?(body, "leader_name")
      assert body["max_size"] == 4
      assert length(body["members"]) == 1
      refute Map.has_key?(hd(body["members"]), "email")
    end

    test "returns conflict if already in a party", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, _party} = Parties.create_party(user, %{})

      conn =
        conn
        |> auth_conn(user)
        |> post("/api/v1/parties", %{})

      assert json_response(conn, 409)["error"] == "already_in_party"
    end

    test "requires auth", %{conn: conn} do
      conn = post(conn, "/api/v1/parties", %{})
      assert conn.status == 401
    end
  end

  describe "GET /api/v1/parties/me" do
    test "returns current party", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(user, %{max_size: 4})

      conn =
        conn
        |> auth_conn(user)
        |> get("/api/v1/parties/me")

      body = json_response(conn, 200)["data"]
      assert body["id"] == party.id
      assert body["leader_id"] == user.id
      assert Map.has_key?(body, "leader_name")
      assert Enum.all?(body["members"], fn m -> not Map.has_key?(m, "email") end)
    end

    test "returns 404 when not in a party", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> auth_conn(user)
        |> get("/api/v1/parties/me")

      assert json_response(conn, 404)["error"] == "not_in_party"
    end
  end

  describe "POST /api/v1/parties/leave" do
    test "leaves the party", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/parties/leave")

      assert json_response(conn, 200) == %{"ok" => true}

      # Party should still exist (leader didn't leave)
      assert Parties.get_party(party.id) != nil
    end

    test "the last member leaving disbands the party", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/leave")

      assert json_response(conn, 200) == %{"ok" => true}
      assert is_nil(Parties.get_party(party.id))
    end

    test "a leader leaving hands the party on rather than ending it", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/leave")

      assert json_response(conn, 200) == %{"ok" => true}
      assert Parties.get_party(party.id).leader_id == member.id
    end
  end

  describe "POST /api/v1/parties/disband" do
    test "the leader ends the party for everyone", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/disband")

      assert json_response(conn, 200) == %{"ok" => true}
      assert is_nil(Parties.get_party(party.id))
      assert is_nil(Gamend.Accounts.get_user(member.id).party_id)
    end

    # Ending it is the leader's call; a member who wants out has leave, which
    # takes only them.
    test "a member cannot end the party", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/parties/disband")

      assert json_response(conn, 403)["error"] == "not_party_leader"
      assert Parties.get_party(party.id)
    end

    test "returns 404 when not in a party", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> auth_conn(user)
        |> post("/api/v1/parties/disband")

      assert json_response(conn, 404)["error"] == "not_in_party"
    end
  end

  describe "party invites" do
    # The leader may invite friends, so each invitee is made one first.
    defp befriend(a, b) do
      {:ok, request} = Gamend.Friends.create_request(a, b.id)
      {:ok, _} = Gamend.Friends.accept_friend_request(request.id, b)
    end

    test "invite, list both ways, accept, cancel and decline", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      [joiner, cancelled, decliner] = for _ <- 1..3, do: AccountsFixtures.user_fixture()
      Enum.each([joiner, cancelled, decliner], &befriend(leader, &1))

      party =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties", %{max_size: 4})
        |> json_response(201)
        |> Map.fetch!("data")

      for user <- [joiner, cancelled, decliner] do
        assert conn
               |> auth_conn(leader)
               |> post("/api/v1/parties/invite", %{target_user_id: user.id})
               |> json_response(200) == %{"ok" => true}
      end

      %{"data" => sent, "meta" => %{"total_count" => 3}} =
        conn |> auth_conn(leader) |> get("/api/v1/parties/invitations/sent") |> json_response(200)

      assert Enum.sort(Enum.map(sent, & &1["recipient_id"])) ==
               Enum.sort([joiner.id, cancelled.id, decliner.id])

      %{"data" => [received]} =
        conn |> auth_conn(joiner) |> get("/api/v1/parties/invitations") |> json_response(200)

      assert received["party_id"] == party["id"]
      assert received["sender_id"] == leader.id

      joined =
        conn
        |> auth_conn(joiner)
        |> post("/api/v1/parties/invite/accept", %{party_id: party["id"]})
        |> json_response(200)
        |> Map.fetch!("data")

      assert Enum.any?(joined["members"], &(&1["id"] == joiner.id))

      assert conn
             |> auth_conn(leader)
             |> post("/api/v1/parties/invite/cancel", %{target_user_id: cancelled.id})
             |> json_response(200) == %{"ok" => true}

      assert conn
             |> auth_conn(decliner)
             |> post("/api/v1/parties/invite/decline", %{party_id: party["id"]})
             |> json_response(200) == %{"ok" => true}

      assert conn
             |> auth_conn(cancelled)
             |> get("/api/v1/parties/invitations")
             |> json_response(200)
             |> Map.fetch!("data") == []

      assert conn
             |> auth_conn(decliner)
             |> get("/api/v1/parties/invitations")
             |> json_response(200)
             |> Map.fetch!("data") == []
    end
  end

  describe "POST /api/v1/parties/kick" do
    test "leader can kick a member", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/kick", %{target_user_id: member.id})

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "non-leader cannot kick", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/parties/kick", %{target_user_id: leader.id})

      assert json_response(conn, 403)["error"] == "not_leader"
    end
  end

  describe "PATCH /api/v1/parties" do
    test "leader can update party", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      conn =
        conn
        |> auth_conn(leader)
        |> patch("/api/v1/parties", %{max_size: 8})

      body = json_response(conn, 200)["data"]
      assert body["max_size"] == 8
    end
  end

  describe "POST /api/v1/parties/create_lobby" do
    test "leader creates lobby for whole party", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)
      set_all_online([leader, member])

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/create_lobby", %{title: "party-lobby", max_users: 8})

      assert conn.status == 201
      body = json_response(conn, 201)["data"]
      assert body["title"] == "party-lobby"

      # Party should still exist
      assert Parties.get_party(party.id) != nil
    end

    test "non-leader cannot create lobby", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/parties/create_lobby", %{title: "nope"})

      assert json_response(conn, 403)["error"] == "not_leader"
    end
  end

  describe "POST /api/v1/parties/join_lobby/:id" do
    test "leader joins lobby with whole party", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)
      set_all_online([leader, member])

      # Create lobby with different host
      host = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "existing-lobby", host_id: host.id})

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/join_lobby/#{lobby.id}")

      body = json_response(conn, 200)["data"]
      assert body["id"] == lobby.id

      # Party should still exist
      assert Parties.get_party(party.id) != nil
    end

    test "fails when lobby too full", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member1 = AccountsFixtures.user_fixture()
      member2 = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      set_all_online([leader, member1, member2])

      # Create a tiny lobby
      host = AccountsFixtures.user_fixture()

      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "tiny-lobby", host_id: host.id, max_users: 3})

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/join_lobby/#{lobby.id}")

      assert json_response(conn, 403)["error"] == "not_enough_space"
    end
  end

  # Each reason answers with the status `GamendWeb.ErrorStatus` gives it, the
  # same from every endpoint: a catch-all clause used to pick one per site.
  describe "the status follows the reason" do
    setup do
      previous = Application.get_env(:gamend_core, :hooks_module)
      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)
      :ok
    end

    defp befriended(leader) do
      target = AccountsFixtures.user_fixture()
      {:ok, request} = Gamend.Friends.create_request(leader, target.id)
      {:ok, _} = Gamend.Friends.accept_friend_request(request.id, target)
      target
    end

    test "updating while in no party is 404 not_in_party, not 400", %{conn: conn} do
      conn =
        conn
        |> auth_conn(AccountsFixtures.user_fixture())
        |> patch("/api/v1/parties", %{max_size: 6})

      assert json_response(conn, 404)["error"] == "not_in_party"
    end

    test "a party lobby with a member offline is 403 members_offline, not 409", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(AccountsFixtures.user_fixture(), party)
      set_all_online([leader])

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/create_lobby", %{title: "party-lobby"})

      assert json_response(conn, 403)["error"] == "members_offline"
    end

    test "inviting a player who blocked a member is 403 blocked, not 422", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member, party)
      target = befriended(leader)
      {:ok, _} = Gamend.Friends.block_user(target, member.id)

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/invite", %{target_user_id: target.id})

      assert json_response(conn, 403)["error"] == "blocked"
    end

    test "a hook vetoing an update is 403 rejected, not 422 unexpected_error", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      Application.put_env(:gamend_core, :hooks_module, GamendWeb.PartyControllerTest.VetoAll)

      conn = conn |> auth_conn(leader) |> patch("/api/v1/parties", %{max_size: 6})

      assert %{"error" => "rejected", "message" => "Settings are locked"} =
               json_response(conn, 403)
    end

    test "a hook vetoing a join is 403 rejected, not 422 unexpected_error", %{conn: conn} do
      leader = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      target = befriended(leader)
      {:ok, _invite} = Parties.invite_to_party(leader, target.id)
      Application.put_env(:gamend_core, :hooks_module, GamendWeb.PartyControllerTest.VetoAll)

      conn =
        conn
        |> auth_conn(target)
        |> post("/api/v1/parties/invite/accept", %{party_id: party.id})

      assert %{"error" => "rejected", "message" => ":crew_only"} = json_response(conn, 403)
      refute Accounts.get_user(target.id).party_id
    end
  end
end
