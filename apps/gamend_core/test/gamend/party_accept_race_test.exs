defmodule Gamend.PartyAcceptRaceTest do
  @moduledoc """
  Accepting a party invite leaves the player's current party first. A kick
  from that party landing at the same moment must not fail the accept: the
  player is out of the party either way, which is all the join needs.

  `Gamend.MembershipConcurrencyTest` met this once in a few full runs, amid a
  random storm of moves; here the two moves race each other directly, round
  after round, so the window is hit far more often.
  """
  use Gamend.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Parties
  alias Gamend.Repo

  @rounds 25

  setup do
    [leader_a, leader_b, player] = players = for _ <- 1..3, do: AccountsFixtures.user_fixture()

    # Party invites need the leader and the player connected and online.
    ids = Enum.map(players, & &1.id)
    Repo.update_all(from(u in User, where: u.id in ^ids), set: [is_online: true])
    {:ok, group} = Groups.create_group(leader_a.id, %{title: "race-#{System.unique_integer()}"})
    for p <- [leader_b, player], do: {:ok, _} = Groups.join_group(p.id, group.id)

    %{leader_a: leader_a, leader_b: leader_b, player: player}
  end

  test "a kick from the current party never fails an accept", ctx do
    for _ <- 1..@rounds do
      {:ok, party_a} = Parties.create_party(me(ctx.leader_a), %{max_size: 4})
      {:ok, _} = Parties.invite_to_party(me(ctx.leader_a), ctx.player.id)
      {:ok, _} = Parties.accept_party_invite(me(ctx.player), party_a.id)

      {:ok, party_b} = Parties.create_party(me(ctx.leader_b), %{max_size: 4})
      {:ok, _} = Parties.invite_to_party(me(ctx.leader_b), ctx.player.id)

      kick = Task.async(fn -> Parties.kick_member(me(ctx.leader_a), ctx.player.id) end)
      accept = Task.async(fn -> Parties.accept_party_invite(me(ctx.player), party_b.id) end)
      # Generous, as in `race/2` of `Gamend.GroupAdminRaceTest`: a `:global`
      # lock's waiter backs off by a growing random sleep.
      _kicked_or_already_gone = Task.await(kick, 60_000)

      assert {:ok, _} = Task.await(accept, 60_000)
      assert me(ctx.player).party_id == party_b.id

      for p <- [ctx.player, ctx.leader_a, ctx.leader_b], me(p).party_id do
        {:ok, _} = Parties.leave_party(me(p))
      end
    end
  end

  defp me(player), do: Repo.get!(User, player.id)
end
