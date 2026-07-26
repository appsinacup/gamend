defmodule GameServer.ReadyChecksEdgeCasesTest do
  @moduledoc """
  The awkward orderings: answers that arrive after a check resolved, a deadline_at
  racing a last-second ready, membership changing under an open check.

  The property every one of these asserts is the same: **a check resolves
  exactly once**. Passing and failing are terminal, so no sequence of events may
  produce two resolutions — a timed-out check that later fills up must not also
  fire `after_ready_check_passed`.
  """
  use GameServer.DataCase

  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.ReadyChecks
  alias GameServer.ReadyChecks.Check

  setup do
    host = AccountsFixtures.user_fixture()
    alice = AccountsFixtures.user_fixture()
    bob = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "edge-room", host_id: host.id, max_users: 4})
    {:ok, _} = Lobbies.join_lobby(alice, lobby.id)
    {:ok, _} = Lobbies.join_lobby(bob, lobby.id)

    %{host: host, alice: alice, bob: bob, lobby: lobby, members: [host.id, alice.id, bob.id]}
  end

  defp expire_now(check) do
    Repo.update_all(from(c in Check, where: c.id == ^check.id),
      set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    ReadyChecks.expire_due()
  end

  defp state_of(check_id, user_id) do
    check_id
    |> ReadyChecks.get_check()
    |> Map.fetch!(:participants)
    |> Enum.find_value(&if(&1.user_id == user_id, do: &1.state))
  end

  describe "answering after the check already resolved" do
    test "un-readying after everyone was ready cannot re-open a passed check", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      {:ok, passed} = ReadyChecks.respond(ctx.bob, true)
      assert passed.status == "passed"

      # The check is no longer pending, so it is no longer the caller's open
      # one — the answer has nowhere to go rather than reviving the check.
      assert {:error, :no_open_check} = ReadyChecks.respond(ctx.alice, false)

      still = ReadyChecks.get_check(check.id)
      assert still.status == "passed"
      assert state_of(check.id, ctx.alice.id) == "ready"
    end

    test "readying after a timeout does not resurrect or double-resolve it", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)

      assert expire_now(check) == 1
      failed = ReadyChecks.get_check(check.id)
      assert failed.status == "failed"
      assert failed.reason == "timeout"

      # Bob answers a beat too late: the check stays failed, and crucially it
      # does not flip to "passed" just because everyone is now ready.
      assert {:error, :no_open_check} = ReadyChecks.respond(ctx.bob, true)

      after_late = ReadyChecks.get_check(check.id)
      assert after_late.status == "failed"
      assert after_late.reason == "timeout"
      assert state_of(check.id, ctx.bob.id) == "timed_out"
    end

    test "answer_for/3 on a resolved check is refused", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      {:ok, _} = ReadyChecks.cancel(check)

      assert {:error, :already_resolved} = ReadyChecks.answer_for(check, ctx.alice.id, true)
    end

    test "cancelling twice is refused rather than resolving twice", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      {:ok, cancelled} = ReadyChecks.cancel(check)
      assert cancelled.status == "cancelled"

      assert {:error, :already_resolved} = ReadyChecks.cancel(check)
    end
  end

  describe "exactly one terminal event per check" do
    setup do
      GameServer.Lobbies.subscribe_lobby("dummy")
      :ok
    end

    test "a timeout emits ready_check_failed and never ready_check_passed", ctx do
      Lobbies.subscribe_lobby(ctx.lobby.id)
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      assert_receive {:ready_check_event, "ready_check_started", _}

      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      assert_receive {:ready_check_event, "ready_check_updated", _}

      assert expire_now(check) == 1
      assert_receive {:ready_check_event, "ready_check_failed", %{reason: "timeout"}}

      # Nothing else lands, in particular no "passed".
      refute_receive {:ready_check_event, "ready_check_passed", _}, 100
    end

    test "passing emits ready_check_passed once", ctx do
      Lobbies.subscribe_lobby(ctx.lobby.id)
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      assert_receive {:ready_check_event, "ready_check_started", _}

      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      assert_receive {:ready_check_event, "ready_check_updated", _}
      {:ok, _} = ReadyChecks.respond(ctx.bob, true)
      assert_receive {:ready_check_event, "ready_check_passed", _}

      # Expiry runs anyway (the sweep does not know it passed) and stays silent.
      assert expire_now(check) == 0
      refute_receive {:ready_check_event, "ready_check_failed", _}, 100
    end

    test "expire_due/0 skips a check that resolved between select and lock", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)

      Repo.update_all(from(c in Check, where: c.id == ^check.id),
        set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      # Resolve it first, then expire the row the sweep already selected.
      {:ok, _} = ReadyChecks.cancel(check)
      assert ReadyChecks.expire(check) == :noop
      assert ReadyChecks.get_check(check.id).status == "cancelled"
    end
  end

  describe "timeout bookkeeping" do
    test "a decline stays declined; only the silent become timed_out", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, false)

      assert expire_now(check) == 1

      assert state_of(check.id, ctx.host.id) == "ready"
      assert state_of(check.id, ctx.alice.id) == "declined"
      assert state_of(check.id, ctx.bob.id) == "timed_out"

      # Both non-ready players are on the host's list, for different reasons.
      not_ready = check.id |> ReadyChecks.get_check() |> ReadyChecks.not_ready()

      assert Enum.map(not_ready, & &1.user_id) |> Enum.sort() ==
               Enum.sort([ctx.alice.id, ctx.bob.id])
    end

    test "a check with no deadline_at is never expired", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, timeout_ms: nil)
      assert check.deadline_at == nil

      assert ReadyChecks.expire_due() == 0
      assert ReadyChecks.get_check(check.id).status == "pending"
    end

    test "a deadline_at in the future is not expired early", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, timeout_ms: 60_000)

      assert ReadyChecks.expire_due() == 0
      assert ReadyChecks.get_check(check.id).status == "pending"
    end
  end

  describe "membership changes against a resolved check" do
    test "leaving after the check passed leaves it untouched", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)
      {:ok, _} = ReadyChecks.respond(ctx.bob, true)

      {:ok, _} = Lobbies.leave_lobby(ctx.bob)

      passed = ReadyChecks.get_check(check.id)
      assert passed.status == "passed"
      # The historical answer survives: the check records what happened.
      assert length(passed.participants) == 3
      assert state_of(check.id, ctx.bob.id) == "ready"
    end

    test "joining after the check resolved adds nobody", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members)
      {:ok, _} = ReadyChecks.cancel(check)

      late = AccountsFixtures.user_fixture()
      {:ok, _} = Lobbies.join_lobby(late, ctx.lobby.id)

      assert length(ReadyChecks.get_check(check.id).participants) == 3
      assert state_of(check.id, late.id) == nil
    end

    test "the last un-ready member leaving passes the check", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, true)

      {:ok, _} = Lobbies.leave_lobby(ctx.bob)

      assert ReadyChecks.get_check(check.id).status == "passed"
    end

    test "a member who declined leaving passes the check for the rest", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = ReadyChecks.respond(ctx.alice, false)
      {:ok, _} = ReadyChecks.respond(ctx.bob, true)
      assert ReadyChecks.get_check(check.id).status == "pending"

      {:ok, _} = Lobbies.leave_lobby(ctx.alice)

      assert ReadyChecks.get_check(check.id).status == "passed"
    end

    test "deleting a user cascades their answer away", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, ctx.members, opened_by: ctx.host.id)
      {:ok, _} = GameServer.Accounts.delete_user(ctx.bob)

      assert length(ReadyChecks.get_check(check.id).participants) == 2
    end
  end

  describe "open/3 input handling" do
    test "duplicate ids produce one participant each", ctx do
      {:ok, check} =
        ReadyChecks.open(ctx.lobby, [ctx.alice.id, ctx.alice.id, ctx.bob.id])

      assert length(check.participants) == 2
    end

    test "a participant list of only nils is refused", ctx do
      assert {:error, :no_participants} = ReadyChecks.open(ctx.lobby, [nil, nil])
    end

    test "past the participant cap it is refused", ctx do
      ids =
        Enum.map(1..(GameServer.Limits.get(:max_ready_check_participants) + 1), fn _ ->
          Ecto.UUID.generate()
        end)

      assert {:error, :too_many_participants} = ReadyChecks.open(ctx.lobby, ids)
    end

    test "a second check on the same lobby loses the unique index race", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.alice.id])

      # Different players, same lobby: `already_pending` cannot catch this, so
      # the partial unique index is what holds the invariant.
      assert {:error, _} = ReadyChecks.open(ctx.lobby, [ctx.bob.id])
      assert ReadyChecks.count_checks(lobby_id: ctx.lobby.id) == 1
    end

    test "a vetoing hook blocks the check", ctx do
      defmodule VetoHook do
        use GameServerWeb.TestSupport.NoopHooks

        @impl true
        def before_ready_check_open(_subject, _user_ids), do: {:error, :not_now}
      end

      previous = Application.get_env(:game_server_core, :hooks_module)
      Application.put_env(:game_server_core, :hooks_module, VetoHook)
      on_exit(fn -> Application.put_env(:game_server_core, :hooks_module, previous) end)

      assert {:error, {:hook_rejected, _}} = ReadyChecks.open(ctx.lobby, ctx.members)
      assert ReadyChecks.pending_for_lobby(ctx.lobby.id) == nil
    end
  end
end
