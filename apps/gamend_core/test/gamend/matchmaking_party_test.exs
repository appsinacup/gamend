defmodule Gamend.MatchmakingPartyTest do
  @moduledoc """
  Party matchmaking: a party is matched as an indivisible unit, only its leader
  may queue it, and it leaves the queue as one.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Limits
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Matcher
  alias Gamend.Matchmaking.Worker
  alias Gamend.Parties

  defp online_user do
    user = AccountsFixtures.unconfirmed_user_fixture()
    {:ok, user} = user |> Ecto.Changeset.change(is_online: true) |> Repo.update()
    user
  end

  # Builds a party of `size` (leader first). Membership is set directly:
  # invite_to_party/2 requires live presence, which is not what is under test.
  defp party_of(size) do
    leader = online_user()
    {:ok, party} = Parties.create_party(leader)

    members =
      for _ <- 2..size//1 do
        user = online_user()
        {:ok, user} = user |> Ecto.Changeset.change(party_id: party.id) |> Repo.update()
        user
      end

    {party, [Repo.reload(leader) | members]}
  end

  defp lobby_of(user_id) do
    Matchmaking.list_tickets([])
    |> Enum.find(&(&1.user_id == user_id))
    |> then(& &1.match_id)
  end

  describe "queueing a party" do
    test "creates one ticket per member, all sharing the party id" do
      {party, [leader | _] = crew} = party_of(3)

      assert {:ok, ticket} = Matchmaking.join(leader, %{"mode" => "ranked"}, 2, 5)
      assert ticket.user_id == leader.id
      assert ticket.party_id == party.id

      queued = Matchmaking.list_tickets(status: "queued")
      assert length(queued) == 3
      assert Enum.all?(queued, &(&1.party_id == party.id))
      assert Enum.sort(Enum.map(queued, & &1.user_id)) == Enum.sort(Enum.map(crew, & &1.id))
    end

    test "a member cannot queue — only the leader" do
      {_party, [_leader, member | _]} = party_of(3)

      assert {:error, :not_party_leader} = Matchmaking.join(member, %{"mode" => "ranked"})
      assert Matchmaking.stats().queued == 0
    end

    test "a party that cannot fit in max_players is rejected" do
      {_party, [leader | _]} = party_of(3)

      assert {:error, :party_too_large} = Matchmaking.join(leader, %{"mode" => "duel"}, 2, 2)
      assert Matchmaking.stats().queued == 0
    end

    test "a party holding a blocked pair is rejected rather than silently split" do
      # Reachable by the most ordinary route: you cannot be invited into a party
      # with someone you blocked, but you can block someone already in it.
      {_party, [leader, m1, m2]} = party_of(3)
      {:ok, _} = Gamend.Friends.block_user(m1, m2.id)

      assert {:error, :party_has_blocked_pair} =
               Matchmaking.join(leader, %{"mode" => "trio"}, 3, 3)

      assert Matchmaking.stats().queued == 0
    end

    test "a block against an outsider does not block the party from queueing" do
      {_party, [leader, m1 | _]} = party_of(3)
      {:ok, _} = Gamend.Friends.block_user(m1, online_user().id)

      assert {:ok, _} = Matchmaking.join(leader, %{"mode" => "trio"}, 3, 3)
      assert Matchmaking.stats().queued == 3
    end

    test "queueing twice is rejected rather than self-matching" do
      user = online_user()
      assert {:ok, _} = Matchmaking.join(user, %{"mode" => "duel"}, 2, 2)
      assert {:error, :already_queued} = Matchmaking.join(user, %{"mode" => "duel"}, 2, 2)
      assert Matchmaking.stats().queued == 1
    end

    test "a party whose member is already queued solo is rejected" do
      {_party, [leader, member | _]} = party_of(3)
      {:ok, _} = Matchmaking.join(%{member | party_id: nil}, %{"mode" => "ranked"})

      assert {:error, :already_queued} = Matchmaking.join(leader, %{"mode" => "ranked"}, 2, 5)
    end

    defmodule DisbandOnJoinHook do
      use Gamend.TestSupport.NoopHooks

      @impl true
      def before_matchmaking_join(user, attrs) do
        {:ok, :disbanded} = Parties.disband(Parties.get_party!(user.party_id))
        {:ok, {user, attrs}}
      end
    end

    test "queueing a party disbanded as it is read answers not_found and writes no tickets" do
      {party, [leader | _]} = party_of(2)

      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, DisbandOnJoinHook)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gamend_core, :hooks_module, previous),
          else: Application.delete_env(:gamend_core, :hooks_module)
      end)

      assert Matchmaking.join(leader, %{"mode" => "duo"}, 2, 2) == {:error, :not_found}
      assert Parties.get_party(party.id) == nil
      assert Matchmaking.count_tickets([]) == 0
    end
  end

  describe "matching" do
    test "a party is never split across lobbies" do
      # 3-party + 1 solo into 2-player lobbies must not seat two members
      # together and strand the third with a stranger.
      {_party, [leader | _] = crew} = party_of(3)
      assert {:error, :party_too_large} = Matchmaking.join(leader, %{"mode" => "duel"}, 2, 2)

      # With room for the whole party, they land together.
      assert {:ok, _} = Matchmaking.join(leader, %{"mode" => "duel"}, 2, 4)
      solo = online_user()
      assert {:ok, _} = Matchmaking.join(solo, %{"mode" => "duel"}, 2, 4)

      assert Worker.sweep() == 1

      lobbies = Enum.map(crew, &lobby_of(&1.id))
      assert Enum.uniq(lobbies) |> length() == 1
      assert hd(lobbies) != nil
      assert lobby_of(solo.id) == hd(lobbies)
    end

    test "two parties that cannot share a lobby both stay queued" do
      # 3 + 2 = 5 players but only 4 seats, and neither party reaches min=4
      # alone. Splitting either one would fill the lobby, so this is exactly the
      # case that must NOT match.
      {_a, [leader_a | _] = crew_a} = party_of(3)
      {_b, [leader_b | _] = crew_b} = party_of(2)

      {:ok, _} = Matchmaking.join(leader_a, %{"mode" => "duel"}, 4, 4)
      {:ok, _} = Matchmaking.join(leader_b, %{"mode" => "duel"}, 4, 4)

      assert Worker.sweep() == 0
      assert Matchmaking.stats().queued == 5
      assert Enum.all?(crew_a ++ crew_b, &(lobby_of(&1.id) == nil))
    end

    test "a solo completes a party that is one seat short" do
      {_party, [leader | _] = crew} = party_of(3)
      {:ok, _} = Matchmaking.join(leader, %{"mode" => "duel"}, 4, 4)
      assert Worker.sweep() == 0

      solo = online_user()
      {:ok, _} = Matchmaking.join(solo, %{"mode" => "duel"}, 4, 4)
      assert Worker.sweep() == 1

      lobbies = Enum.map(crew, &lobby_of(&1.id))
      assert Enum.uniq(lobbies) |> length() == 1
      assert lobby_of(solo.id) == hd(lobbies)
    end

    test "Matcher keeps party tickets together and solos separate" do
      party_id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      party = for i <- 1..3, do: ticket(party_id, now, i, 2, 4)
      solo = ticket(nil, DateTime.add(now, 1, :second), 9, 2, 4)

      # Input order is irrelevant: the matcher groups and sorts by queued_at.
      {[match], remaining} = Matcher.form_matches([solo | party])

      assert length(match) == 4
      assert remaining == []
    end

    test "Matcher leaves both parties queued when neither fits with the other" do
      now = DateTime.utc_now()
      a = for i <- 1..3, do: ticket("party-a", now, i, 4, 4)
      b = for i <- 1..2, do: ticket("party-b", DateTime.add(now, 1, :second), i, 4, 4)

      assert {[], remaining} = Matcher.form_matches(a ++ b)
      assert length(remaining) == 5
    end
  end

  describe "leaving the queue" do
    test "any member cancelling removes the whole party" do
      {_party, [leader, member | _]} = party_of(3)
      {:ok, _} = Matchmaking.join(leader, %{"mode" => "ranked"}, 2, 5)

      assert Matchmaking.cancel(member.id) == 3
      assert Matchmaking.stats().queued == 0
    end

    test "an offline player is kept for the grace period" do
      user = online_user()
      {:ok, _} = Matchmaking.join(user, %{"mode" => "ranked"})

      # Offline, but only just — the ticket survives.
      go_offline(user, 10_000)
      assert Matchmaking.prune_offline() == 0
      assert Matchmaking.stats().queued == 1

      go_offline(user, Limits.get(:matchmaking_offline_grace_ms) + 1_000)
      assert Matchmaking.prune_offline() == 1
      assert Matchmaking.stats().queued == 0
    end

    test "one member timing out takes the whole party out of the queue" do
      {_party, [leader, member | _]} = party_of(3)
      {:ok, _} = Matchmaking.join(leader, %{"mode" => "ranked"}, 2, 5)

      go_offline(member, Limits.get(:matchmaking_offline_grace_ms) + 1_000)

      assert Matchmaking.prune_offline() == 3
      assert Matchmaking.stats().queued == 0
    end

    test "a never-connected HTTP queuer gets the grace period from queued_at" do
      user = AccountsFixtures.unconfirmed_user_fixture()
      assert user.is_online == false
      assert user.last_seen_at == nil

      {:ok, ticket} = Matchmaking.join(user, %{"mode" => "ranked"})
      assert Matchmaking.prune_offline() == 0

      stale = DateTime.add(DateTime.utc_now(), -Limits.get(:matchmaking_offline_grace_ms) - 1_000)
      ticket |> Ecto.Changeset.change(queued_at: stale) |> Repo.update!()

      assert Matchmaking.prune_offline() == 1
    end
  end

  defp go_offline(user, ms_ago) do
    seen =
      DateTime.utc_now()
      |> DateTime.add(-ms_ago, :millisecond)
      |> DateTime.truncate(:second)

    user
    |> Ecto.Changeset.change(is_online: false, last_seen_at: seen)
    |> Repo.update!()
  end

  defp ticket(party_id, queued_at, seq, min, max) do
    %Gamend.Matchmaking.Ticket{
      id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      party_id: party_id,
      min_players: min,
      max_players: max,
      timeout_ms: 30_000,
      queued_at: DateTime.add(queued_at, seq, :millisecond)
    }
  end
end
