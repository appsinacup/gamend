defmodule GamendWeb.Api.V1.ReadyCheckControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias Gamend.ReadyChecks
  alias GamendWeb.Auth.Guardian

  defp authed(user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    build_conn() |> put_req_header("authorization", "Bearer " <> token)
  end

  setup do
    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "ready-room", host_id: host.id, max_users: 4})
    {:ok, _} = Lobbies.join_lobby(member, lobby.id)

    %{host: host, member: member, lobby: lobby}
  end

  describe "POST /api/v1/lobbies/ready_check" do
    test "the host opens one over every member", ctx do
      conn = post(authed(ctx.host), "/api/v1/lobbies/ready_check", %{})

      assert %{"kind" => "ready", "status" => "pending", "total" => 2} =
               json_response(conn, 201)["data"]

      # The host answered by opening it.
      assert json_response(conn, 201)["data"]["ready_count"] == 1
    end

    test "a non-host member is refused", ctx do
      conn = post(authed(ctx.member), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 403)["error"] == "not_host"
    end

    test "no caller may open one on a hostless lobby", _ctx do
      user = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "ranked", hostless: true})
      {:ok, _} = Lobbies.join_lobby(user, lobby.id)

      conn = post(authed(user), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 403)["error"] == "not_host"
    end

    test "a caller in no lobby gets 404", _ctx do
      conn = post(authed(AccountsFixtures.user_fixture()), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 404)["error"] == "not_in_lobby"
    end

    # A hostless lobby has no owner until the game pins one. Once it does, that
    # user opens the board — the same authority that edits and kicks.
    test "the pinned WebRTC host of a hostless lobby may open one", _ctx do
      user = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "ranked-pinned", hostless: true})
      {:ok, _} = Lobbies.join_lobby(user, lobby.id)

      conn = post(authed(user), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 403)["error"] == "not_host"

      {:ok, _} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: user.id)

      conn = post(authed(user), "/api/v1/lobbies/ready_check", %{})
      assert %{"kind" => "ready", "status" => "pending"} = json_response(conn, 201)["data"]
    end

    # These endpoints take no lobby id, so they still resolve the room from the
    # caller's own `lobby_id`: authority alone is not enough to reach them.
    test "an authority seated in no lobby still cannot reach it", _ctx do
      server = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "ranked-headless", hostless: true})
      {:ok, _} = Lobbies.join_lobby(AccountsFixtures.user_fixture(), lobby.id)

      {:ok, lobby} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: server.id)

      assert Lobbies.can_manage_lobby?(server, lobby)

      conn = post(authed(server), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 404)["error"] == "not_in_lobby"
    end

    test "a second open resets the board instead of refusing", ctx do
      first = post(authed(ctx.host), "/api/v1/lobbies/ready_check", %{})
      first_id = json_response(first, 201)["data"]["id"]

      conn = post(authed(ctx.host), "/api/v1/lobbies/ready_check", %{})
      second_id = json_response(conn, 201)["data"]["id"]

      assert second_id != first_id
      # The replaced board is quietly cancelled with reason "reset".
      assert %{status: "cancelled", reason: "reset"} =
               Map.take(ReadyChecks.get_check(first_id), [:status, :reason])
    end

    test "honours an explicit timeout", ctx do
      conn = post(authed(ctx.host), "/api/v1/lobbies/ready_check", %{"timeout_ms" => 60_000})

      deadline_at =
        json_response(conn, 201)["data"]["deadline_at"] |> NaiveDateTime.from_iso8601!()

      assert NaiveDateTime.diff(deadline_at, NaiveDateTime.utc_now()) > 30
    end

    test "requires authentication" do
      conn = post(build_conn(), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/me/ready_check" do
    test "returns null lanes when there is none", ctx do
      conn = get(authed(ctx.member), "/api/v1/me/ready_check")
      assert json_response(conn, 200)["data"] == %{"lobby" => nil, "party" => nil}
    end

    test "a ready check lists participants", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

      conn = get(authed(ctx.member), "/api/v1/me/ready_check")
      data = json_response(conn, 200)["data"]["lobby"]

      assert data["your_state"] == "pending"
      assert length(data["participants"]) == 2
      assert Enum.all?(data["participants"], &is_binary(&1["display_name"]))
    end

    test "an accept check hides who the caller was paired with", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], kind: "accept")

      conn = get(authed(ctx.member), "/api/v1/me/ready_check")
      data = json_response(conn, 200)["data"]["lobby"]

      refute Map.has_key?(data, "participants")
      assert data["total"] == 2
      assert data["your_state"] == "pending"
    end

    test "the lobby and party lanes are reported side by side", ctx do
      {:ok, party} = Parties.create_party(ctx.host)
      {:ok, _} = ReadyChecks.open(party, [ctx.host.id])
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

      conn = get(authed(ctx.host), "/api/v1/me/ready_check")
      data = json_response(conn, 200)["data"]

      assert data["lobby"]["lobby_id"] == ctx.lobby.id
      assert data["party"]["party_id"] == party.id
    end
  end

  describe "POST /api/v1/me/ready_check" do
    setup ctx do
      {:ok, check} =
        ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], opened_by: ctx.host.id)

      Map.put(ctx, :check, check)
    end

    test "answering ready passes the check once everyone has", ctx do
      conn = post(authed(ctx.member), "/api/v1/me/ready_check", %{"ready" => true})

      assert %{"status" => "passed", "ready_count" => 2} = json_response(conn, 200)["data"]
    end

    test "answering not-ready keeps it open", ctx do
      conn = post(authed(ctx.member), "/api/v1/me/ready_check", %{"ready" => false})

      assert %{"status" => "pending", "your_state" => "declined"} =
               json_response(conn, 200)["data"]
    end

    test "answering with no open check is not found", ctx do
      {:ok, _} = ReadyChecks.cancel(ctx.check)

      conn = post(authed(ctx.member), "/api/v1/me/ready_check", %{"ready" => true})
      assert json_response(conn, 404)["error"] == "no_open_check"
    end

    test "an accept answer cannot be revoked", ctx do
      {:ok, _} = ReadyChecks.cancel(ctx.check)
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], kind: "accept")

      post(authed(ctx.member), "/api/v1/me/ready_check", %{"ready" => true})
      conn = post(authed(ctx.member), "/api/v1/me/ready_check", %{"ready" => false})

      assert json_response(conn, 409)["error"] == "not_revocable"
    end

    test "rejects a non-boolean answer", ctx do
      conn = post(authed(ctx.member), "/api/v1/me/ready_check", %{"ready" => "yes"})
      assert json_response(conn, 400)["error"] == "invalid_ready"
    end

    test "rejects an unknown scope", ctx do
      conn =
        post(authed(ctx.member), "/api/v1/me/ready_check", %{
          "ready" => true,
          "scope" => "guild"
        })

      assert json_response(conn, 400)["error"] == "invalid_scope"
    end

    test "scope party answers the party board, not the lobby check", ctx do
      {:ok, party} = Parties.create_party(ctx.member)
      {:ok, party_check} = ReadyChecks.open(party, [ctx.member.id])

      conn =
        post(authed(ctx.member), "/api/v1/me/ready_check", %{
          "ready" => true,
          "scope" => "party"
        })

      assert %{"status" => "passed"} = json_response(conn, 200)["data"]
      assert ReadyChecks.get_check(party_check.id).status == "passed"
      # The lobby check is untouched.
      assert ReadyChecks.get_check(ctx.check.id).status == "pending"
    end
  end

  describe "DELETE /api/v1/lobbies/ready_check" do
    test "the host calls it off", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

      conn = delete(authed(ctx.host), "/api/v1/lobbies/ready_check")
      assert json_response(conn, 200) == %{"ok" => true}

      assert ReadyChecks.get_check(check.id).status == "cancelled"
    end

    test "a member cannot", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

      conn = delete(authed(ctx.member), "/api/v1/lobbies/ready_check")
      assert json_response(conn, 403)["error"] == "not_host"
    end

    test "404 when there is none open", ctx do
      conn = delete(authed(ctx.host), "/api/v1/lobbies/ready_check")
      assert json_response(conn, 404)["error"] == "no_open_check"
    end
  end

  describe "POST /api/v1/parties/ready_check" do
    setup do
      leader = AccountsFixtures.user_fixture()
      mate = AccountsFixtures.user_fixture()
      {:ok, party} = Parties.create_party(leader)
      {:ok, _} = join_party(mate, leader, party)

      %{leader: leader, mate: mate, party: party}
    end

    test "the leader opens one over every member", ctx do
      conn = post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})

      assert %{"kind" => "ready", "status" => "pending", "total" => 2} =
               json_response(conn, 201)["data"]

      assert json_response(conn, 201)["data"]["party_id"] == ctx.party.id
      # The leader answered by opening it.
      assert json_response(conn, 201)["data"]["ready_count"] == 1
    end

    # A party board STANDS — it is "are you coming", asked once and left up, not
    # the countdown a lobby board is. It used to inherit the lobby default, and
    # an expired check reports no participants: the crew's button fell to a
    # disabled "Waiting for captain" and the leader's to a disabled "Waiting for
    # crew", with nothing left that could reopen it. Both were stuck for good.
    test "the board it opens has no deadline", ctx do
      conn = post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})

      assert json_response(conn, 201)["data"]["deadline_at"] == nil
      assert ReadyChecks.get_check(json_response(conn, 201)["data"]["id"]).deadline_at == nil
    end

    test "a caller that wants a fuse still gets one", ctx do
      conn = post(authed(ctx.leader), "/api/v1/parties/ready_check", %{"timeout_ms" => 30_000})

      assert json_response(conn, 201)["data"]["deadline_at"] != nil
    end

    test "a non-leader member is refused", ctx do
      conn = post(authed(ctx.mate), "/api/v1/parties/ready_check", %{})
      assert json_response(conn, 403)["error"] == "not_leader"
    end

    test "a caller in no party gets 404", _ctx do
      conn = post(authed(AccountsFixtures.user_fixture()), "/api/v1/parties/ready_check", %{})
      assert json_response(conn, 404)["error"] == "not_in_party"
    end

    test "a second open resets the board", ctx do
      first = post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})
      first_id = json_response(first, 201)["data"]["id"]

      conn = post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})
      assert json_response(conn, 201)["data"]["id"] != first_id
      assert ReadyChecks.get_check(first_id).status == "cancelled"
    end

    test "the party board does not block the party's lobby check", ctx do
      post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})

      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "co-op", host_id: ctx.leader.id, max_users: 4})

      {:ok, _} = Lobbies.join_lobby(ctx.mate, lobby.id)

      conn = post(authed(ctx.leader), "/api/v1/lobbies/ready_check", %{})
      assert json_response(conn, 201)["data"]["lobby_id"] == lobby.id
      # Both boards open at once, one per lane.
      assert %ReadyChecks.Check{} = ReadyChecks.pending_for_party(ctx.party.id)
      assert %ReadyChecks.Check{} = ReadyChecks.pending_for_lobby(lobby.id)
    end

    test "the leader calls it off", ctx do
      post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})

      conn = delete(authed(ctx.leader), "/api/v1/parties/ready_check")
      assert json_response(conn, 200) == %{"ok" => true}
      assert ReadyChecks.pending_for_party(ctx.party.id) == nil
    end

    test "calling off with no open check is not found", ctx do
      conn = delete(authed(ctx.leader), "/api/v1/parties/ready_check")
      assert json_response(conn, 404)["error"] == "no_open_check"
    end

    test "a mate cannot call it off", ctx do
      post(authed(ctx.leader), "/api/v1/parties/ready_check", %{})

      conn = delete(authed(ctx.mate), "/api/v1/parties/ready_check")
      assert json_response(conn, 403)["error"] == "not_leader"
    end
  end

  defp join_party(user, leader, party) do
    # Members join via invite; wire it through the real flow so the join seam
    # (ready board add) runs exactly as production.
    {:ok, request} = Gamend.Friends.create_request(leader.id, user.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(request.id, user)
    {:ok, _} = Parties.invite_to_party(leader, user.id)
    Parties.accept_party_invite(user, party.id)
  end
end
