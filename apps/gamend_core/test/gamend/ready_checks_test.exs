defmodule Gamend.ReadyChecksTest do
  use Gamend.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.ReadyChecks
  alias Gamend.ReadyChecks.Check
  alias Gamend.ReadyChecks.Participant

  setup do
    host = AccountsFixtures.user_fixture()
    alice = AccountsFixtures.user_fixture()
    bob = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "ready-room", host_id: host.id, max_users: 4})
    {:ok, _} = Lobbies.join_lobby(alice, lobby.id)
    {:ok, _} = Lobbies.join_lobby(bob, lobby.id)

    %{host: host, alice: alice, bob: bob, lobby: lobby, members: [host.id, alice.id, bob.id]}
  end

  defp state_of(check, user_id) do
    check = ReadyChecks.get_check(check.id)
    Enum.find_value(check.participants, &if(&1.user_id == user_id, do: &1.state))
  end

  describe "open/3" do
    test "creates a pending check with one participant per member", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)

      assert check.kind == "ready"
      assert check.status == "pending"
      assert check.lobby_id == ctx.lobby.id
      assert length(check.participants) == 3
      assert Enum.all?(check.participants, &(&1.state == "pending"))
    end

    test "pre-marks the opener ready — clicking the button is their answer", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)

      assert state_of(check, ctx.host.id) == "ready"
      assert state_of(check, ctx.alice.id) == "pending"
    end

    test "defaults the deadline_at from the configured timeout", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)

      assert DateTime.diff(check.deadline_at, DateTime.utc_now()) in 10..16
    end

    test "a ready check may be open-ended", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, timeout_ms: nil)
      assert check.deadline_at == nil
    end

    test "refuses a second check while one is open", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, ctx.members)
      assert {:error, :already_pending} = ReadyChecks.open(ctx.lobby, ctx.members)
    end

    test "refuses a player already in another check", ctx do
      other_host = AccountsFixtures.user_fixture()
      {:ok, other_lobby} = Lobbies.create_lobby(%{title: "other", host_id: other_host.id})
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.alice.id])

      assert {:error, :already_pending} = ReadyChecks.open(other_lobby, [ctx.alice.id])
    end

    test "rejects an empty participant list", ctx do
      assert {:error, :no_participants} = ReadyChecks.open(ctx.lobby, [])
    end

    test "an accept check must have a deadline_at", ctx do
      assert {:error, _} =
               ReadyChecks.open(ctx.lobby, ctx.members, kind: "accept", timeout_ms: nil)
    end

    test "opening a board for a lobby deleted after it was read answers not_found", ctx do
      {:ok, _} = Lobbies.delete_lobby(ctx.lobby)

      assert ReadyChecks.open(ctx.lobby, ctx.members) == {:error, :not_found}
      refute Repo.exists?(from c in Check, where: c.lobby_id == ^ctx.lobby.id)
    end

    test ":members is every member as the board is written", ctx do
      {:ok, _} = Lobbies.leave_lobby(ctx.bob)

      {:ok, check} = ReadyChecks.reset(ctx.lobby, :members, opened_by: ctx.host.id)

      assert check.participants |> Enum.map(& &1.user_id) |> Enum.sort() ==
               Enum.sort([ctx.host.id, ctx.alice.id])
    end

    test "a member who joins while the board is open goes on it, pending", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.alice.id], timeout_ms: nil)
      carol = AccountsFixtures.user_fixture()

      {:ok, _} = Lobbies.join_lobby(carol, ctx.lobby.id)

      assert state_of(check, carol.id) == "pending"
    end

    test "a member who joins after the board passed is not put on it", ctx do
      {:ok, check} =
        ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.alice.id], opened_by: ctx.host.id)

      {:ok, %Check{status: "passed"}} = ReadyChecks.respond(ctx.alice, true)
      carol = AccountsFixtures.user_fixture()

      {:ok, _} = Lobbies.join_lobby(carol, ctx.lobby.id)

      assert length(ReadyChecks.get_check(check.id).participants) == 2
    end
  end

  describe "respond/2 — kind ready" do
    setup ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      Map.put(ctx, :check, check)
    end

    test "passes once everyone answers ready", ctx do
      {:ok, check} = ReadyChecks.respond(ctx.alice, true)
      assert check.status == "pending"

      {:ok, check} = ReadyChecks.respond(ctx.bob, true)
      assert check.status == "passed"
      assert ReadyChecks.passed?(ctx.lobby)
      assert ReadyChecks.pending_for_lobby(ctx.lobby.id) == nil
    end

    test "a decline holds the check open rather than failing it", ctx do
      {:ok, check} = ReadyChecks.respond(ctx.alice, false)

      assert check.status == "pending"
      assert state_of(ctx.check, ctx.alice.id) == "declined"
    end

    test "an answer can be taken back", ctx do
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      {:ok, _} = ReadyChecks.respond(ctx.alice, false)
      assert state_of(ctx.check, ctx.alice.id) == "declined"

      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      assert state_of(ctx.check, ctx.alice.id) == "ready"
    end

    test "answering without an open check fails", ctx do
      {:ok, _} = ReadyChecks.cancel(ctx.check)
      assert {:error, :no_open_check} = ReadyChecks.respond(ctx.alice, true)
    end

    test "answer_for/3 answers on behalf of a bot", ctx do
      {:ok, _} = ReadyChecks.answer_for(ctx.check, ctx.alice.id, true)
      assert state_of(ctx.check, ctx.alice.id) == "ready"
    end
  end

  describe "respond/2 — kind accept" do
    setup ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, kind: "accept")
      Map.put(ctx, :check, check)
    end

    test "one decline fails the whole check", ctx do
      {:ok, _} = ReadyChecks.respond(ctx.host, true)
      {:ok, check} = ReadyChecks.respond(ctx.alice, false)

      assert check.status == "failed"
      assert check.reason == "declined"
    end

    test "an accept cannot be taken back", ctx do
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      assert {:error, :not_revocable} = ReadyChecks.respond(ctx.alice, false)
    end
  end

  describe "concurrency" do
    test "simultaneous answers still pass the check exactly once", ctx do
      # Write skew: each answer counts the other as still pending unless
      # respond/2 serializes write-then-evaluate.
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      parent = self()

      [ctx.alice, ctx.bob]
      |> Enum.map(fn user ->
        Task.async(fn ->
          Sandbox.allow(Gamend.Repo, parent, self())
          ReadyChecks.respond(user, true)
        end)
      end)
      |> Task.await_many(5_000)

      assert ReadyChecks.get_check(check.id).status == "passed"
    end
  end

  describe "expiry" do
    test "fails the check and marks the silent participants timed_out", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)

      # Deadline in the past rather than sleeping.
      Repo.update_all(Check,
        set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      assert ReadyChecks.expire_due() == 1

      expired = ReadyChecks.get_check(check.id)
      assert expired.status == "failed"
      assert expired.reason == "timeout"
      assert state_of(check, ctx.alice.id) == "ready"
      assert state_of(check, ctx.bob.id) == "timed_out"
    end

    test "is idempotent — a resolved check expires to :noop", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, timeout_ms: 1)
      {:ok, _} = ReadyChecks.cancel(check)

      assert ReadyChecks.expire(check) == :noop
      assert ReadyChecks.expire_due() == 0
    end

    test "core kicks nobody when a check times out", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)

      Repo.update_all(Check,
        set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      _ = ReadyChecks.expire_due()

      assert Gamend.Accounts.get_user(ctx.bob.id).lobby_id == ctx.lobby.id
      assert Lobbies.get_lobby(ctx.lobby.id).state == "created"
      assert length(ReadyChecks.not_ready(ReadyChecks.get_check(check.id))) == 2
    end
  end

  describe "answering after the deadline" do
    # A board that ran out of time is still the one on everyone's screen. The
    # clock is not a refusal, so a late answer counts — otherwise the crew
    # stare at a board nobody can touch and nothing reopens it.
    setup ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)

      Repo.update_all(Check, set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)])
      1 = ReadyChecks.expire_due()

      Map.put(ctx, :check, check)
    end

    test "a late yes is recorded on the timed-out board", ctx do
      assert {:ok, _} = ReadyChecks.respond(ctx.alice, true)

      assert state_of(ctx.check, ctx.alice.id) == "ready"
      # Bob never answered, so the board has not come back to life.
      assert ReadyChecks.get_check(ctx.check.id).status == "failed"
    end

    test "the last late yes passes the board", ctx do
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      {:ok, check} = ReadyChecks.respond(ctx.bob, true)

      assert check.status == "passed"
      assert is_nil(check.reason)
    end

    test "a late no is taken too, and leaves the board failed", ctx do
      assert {:ok, _} = ReadyChecks.respond(ctx.alice, false)

      assert state_of(ctx.check, ctx.alice.id) == "declined"
      assert ReadyChecks.get_check(ctx.check.id).status == "failed"
    end

    test "a fresh board supersedes it — the answer lands on the new one", ctx do
      {:ok, new_check} = ReadyChecks.reset(ctx.lobby, ctx.members, timeout_ms: nil)

      {:ok, answered} = ReadyChecks.respond(ctx.alice, true)

      assert answered.id == new_check.id
      assert state_of(ctx.check, ctx.alice.id) == "timed_out"
    end

    test "a cancelled board stays shut — that was somebody's decision", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.alice.id, ctx.bob.id])
      {:ok, _} = ReadyChecks.cancel(check)

      assert ReadyChecks.respond(ctx.alice, true) == {:error, :no_open_check}
    end

    test "an accept check that timed out does not take late answers", ctx do
      # An accept always carries a deadline — the schema requires one — and
      # once it burns the tickets are already back in the queue, so there is
      # nothing left to accept.
      {:ok, _} = ReadyChecks.open(ctx.lobby, ctx.members, kind: "accept", timeout_ms: 1)

      Repo.update_all(Check, set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)])
      _ = ReadyChecks.expire_due()

      assert ReadyChecks.respond(ctx.alice, true) == {:error, :no_open_check}
    end
  end

  describe "membership changes" do
    test "kicking the straggler re-evaluates and can pass the check", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      assert ReadyChecks.get_check(check.id).status == "pending"

      {:ok, _} = Lobbies.kick_user(ctx.host, ctx.lobby, ctx.bob)

      assert ReadyChecks.get_check(check.id).status == "passed"
    end

    test "leaving drops the participant", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = Lobbies.leave_lobby(ctx.bob)

      assert state_of(check, ctx.bob.id) == nil
      assert length(ReadyChecks.get_check(check.id).participants) == 2
    end

    test "a late joiner is added as pending", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      late = AccountsFixtures.user_fixture()
      {:ok, _} = Lobbies.join_lobby(late, ctx.lobby.id)

      assert state_of(check, late.id) == "pending"
    end

    test "the check is cancelled when the last member leaves", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.bob.id])
      {:ok, _} = Lobbies.leave_lobby(ctx.bob)

      assert ReadyChecks.get_check(check.id).status == "cancelled"
    end

    test "deleting the lobby cascades its checks", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      {:ok, _} = Lobbies.delete_lobby(ctx.lobby)

      assert ReadyChecks.get_check(check.id) == nil
    end

    test "a joiner's seat on a board deleted as it is read is dropped and the add answers ok",
         ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      late = AccountsFixtures.user_fixture()
      pid = self()
      handler = {__MODULE__, :delete_check_after_read, System.unique_integer()}

      :telemetry.attach(
        handler,
        [:gamend, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if self() == pid and meta[:source] == "ready_checks" and !Process.get(:check_deleted) do
            Process.put(:check_deleted, true)
            Repo.delete_all(from c in Check, where: c.id == ^check.id)
          end
        end,
        nil
      )

      result = ReadyChecks.add_member(ctx.lobby.id, late.id)
      :telemetry.detach(handler)

      assert Process.get(:check_deleted)
      assert result == :ok
      refute Repo.exists?(from p in Participant, where: p.user_id == ^late.id)
    end
  end

  describe "reads" do
    test "for_user/1 returns only a pending check", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      assert ReadyChecks.for_user(ctx.alice.id).id == check.id

      {:ok, _} = ReadyChecks.cancel(check)
      assert ReadyChecks.for_user(ctx.alice.id) == nil
    end

    test "not_ready/1 lists everyone who did not answer ready", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, false)

      not_ready = check.id |> ReadyChecks.get_check() |> ReadyChecks.not_ready()

      assert not_ready |> Enum.map(& &1.user_id) |> Enum.sort() ==
               Enum.sort([ctx.alice.id, ctx.bob.id])
    end

    test "passed?/1 is false for a lobby that never had one", _ctx do
      {:ok, fresh} =
        Lobbies.create_lobby(%{title: "fresh", host_id: AccountsFixtures.user_fixture().id})

      refute ReadyChecks.passed?(fresh)
    end

    test "stats/1 counts by status", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      {:ok, _} = ReadyChecks.cancel(check)

      assert %{"cancelled" => 1} = ReadyChecks.stats()
    end

    test "list_checks/1 paginates and filters", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      {:ok, _} = ReadyChecks.cancel(check)

      assert [_] = ReadyChecks.list_checks(lobby_id: ctx.lobby.id, page: 1, page_size: 10)
      assert ReadyChecks.count_checks(status: "cancelled") == 1
      assert ReadyChecks.list_checks(status: "passed") == []
    end
  end

  describe "reset/3" do
    test "quietly replaces the open board — no failed event, no failed hook", ctx do
      Phoenix.PubSub.subscribe(Gamend.PubSub, "lobby:#{ctx.lobby.id}")

      {:ok, first} = ReadyChecks.open(ctx.lobby, ctx.members)
      assert_receive {:ready_check_event, "ready_check_started", _}

      {:ok, second} = ReadyChecks.reset(ctx.lobby, ctx.members)

      assert second.id != first.id

      assert %{status: "cancelled", reason: "reset"} =
               Map.take(ReadyChecks.get_check(first.id), [:status, :reason])

      # Only the fresh board is announced; the replaced one dies silently.
      assert_receive {:ready_check_event, "ready_check_started", %{id: id}}
      assert id == second.id
      refute_receive {:ready_check_event, "ready_check_failed", _}
    end

    test "makes passed?/1 false again — a rematch cannot ride the old pass", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      {:ok, _} = ReadyChecks.respond(ctx.bob, true)
      assert ReadyChecks.passed?(ctx.lobby)

      {:ok, _} = ReadyChecks.reset(ctx.lobby, ctx.members)
      refute ReadyChecks.passed?(ctx.lobby)
    end

    test "opens fresh when there was nothing to replace", ctx do
      assert {:ok, %Check{status: "pending"}} = ReadyChecks.reset(ctx.lobby, ctx.members)
    end
  end

  describe "party boards" do
    setup ctx do
      {:ok, party} = Gamend.Parties.create_party(ctx.host)
      Map.put(ctx, :party, party)
    end

    test "a party opens a kind-ready check carrying party_id", ctx do
      {:ok, check} = ReadyChecks.open(ctx.party, [ctx.host.id])

      assert check.kind == "ready"
      assert check.party_id == ctx.party.id
      assert check.lobby_id == nil
    end

    test "the party lane never blocks the match lane", ctx do
      {:ok, _} = ReadyChecks.open(ctx.party, [ctx.host.id])
      assert {:ok, _} = ReadyChecks.open(ctx.lobby, ctx.members)

      # And the other way around: a second board in the *same* lane still
      # conflicts.
      assert {:error, :already_pending} = ReadyChecks.open(ctx.party, [ctx.host.id])
    end

    test "respond/3 scopes the answer to one lane", ctx do
      {:ok, party_check} = ReadyChecks.open(ctx.party, [ctx.host.id])
      {:ok, lobby_check} = ReadyChecks.open(ctx.lobby, ctx.members)

      {:ok, _} = ReadyChecks.respond(ctx.host, true, :party)

      assert ReadyChecks.get_check(party_check.id).status == "passed"
      assert state_of(lobby_check, ctx.host.id) == "pending"
    end

    test "add_party_member/2 and remove_party_member/2 keep the roster true", ctx do
      {:ok, check} = ReadyChecks.open(ctx.party, [ctx.host.id, ctx.alice.id])

      :ok = ReadyChecks.add_party_member(ctx.party.id, ctx.bob.id)
      assert length(ReadyChecks.get_check(check.id).participants) == 3

      # Removing the two who never answered can pass the board outright.
      {:ok, _} = ReadyChecks.respond(ctx.host, true, :party)
      :ok = ReadyChecks.remove_party_member(ctx.party.id, ctx.alice.id)
      :ok = ReadyChecks.remove_party_member(ctx.party.id, ctx.bob.id)

      assert ReadyChecks.get_check(check.id).status == "passed"
      assert ReadyChecks.passed?(ctx.party)
    end

    test "deleting the party cascades its checks", ctx do
      {:ok, check} = ReadyChecks.open(ctx.party, [ctx.host.id])

      {:ok, :disbanded} = Gamend.Parties.leave_party(ctx.host)

      assert ReadyChecks.get_check(check.id) == nil
    end
  end
end
