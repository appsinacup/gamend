defmodule Gamend.PartySeatRaceTest do
  @moduledoc """
  A player creating a party while accepting an invite to another, both at
  once. Create locks the player and the accept locks the party it joins, so
  neither waits on the other; the seat on the player's row has to.

  Postgres only shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Parties
  alias Gamend.Parties.Party
  alias Gamend.Parties.PartyInvite

  @pairs 15

  setup do
    pairs = unboxed(fn -> for _ <- 1..@pairs, do: invited_player() end)
    user_ids = Enum.flat_map(pairs, fn %{player: p, leader: l} -> [p.id, l.id] end)

    cleanup(fn ->
      Repo.update_all(from(u in User, where: u.id in ^user_ids), set: [party_id: nil])
      Repo.delete_all(from p in Party, where: p.leader_id in ^user_ids)
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)

    %{pairs: pairs}
  end

  test "a player ends up in exactly one party, and no party is left without them", %{
    pairs: pairs
  } do
    results =
      pairs
      |> Enum.flat_map(fn %{player: player, party: party} ->
        [
          fn -> Parties.create_party(player, %{}) end,
          fn -> Parties.accept_party_invite(player, party.id) end
        ]
      end)
      |> race()
      |> Enum.chunk_every(2)

    for {%{player: player, party: invited}, [created, accepted]} <- Enum.zip(pairs, results) do
      refute match?({:raised, _}, created), "create raised: #{inspect(created)}"
      refute match?({:raised, _}, accepted), "accept raised: #{inspect(accepted)}"

      seated = unboxed(fn -> Repo.get!(User, player.id).party_id end)

      led =
        unboxed(fn ->
          Repo.all(from p in Party, where: p.leader_id == ^player.id, select: p.id)
        end)

      assert Enum.all?(led, &(&1 == seated)),
             "a party led by the player has no seat for them: #{inspect({created, accepted})}"

      # Either order is fine one after the other: an accept after the create
      # leaves the new party (a party of one disbands) for the invited one.
      # What may not happen is both writing a seat over each other.
      case {created, accepted} do
        {{:ok, _}, {:ok, _}} ->
          assert seated == invited.id

        {{:ok, party}, {:error, :already_in_party}} ->
          assert seated == party.id
          assert invite_status(player, invited) == "pending", "the unused invite still stands"

        {{:error, :already_in_party}, {:ok, _}} ->
          assert seated == invited.id

        other ->
          flunk("unexpected outcome: #{inspect(other)}")
      end
    end
  end

  defp invite_status(player, party) do
    unboxed(fn ->
      Repo.one(
        from i in PartyInvite,
          where: i.recipient_id == ^player.id and i.party_id == ^party.id,
          select: i.status
      )
    end)
  end

  defp invited_player do
    leader = AccountsFixtures.user_fixture()
    player = AccountsFixtures.user_fixture()

    {:ok, request} = Friends.create_request(leader, player.id)
    Friends.accept_friend_request(request.id, player)

    {:ok, party} = Parties.create_party(leader, %{})
    {:ok, _invite} = Parties.invite_to_party(leader, player.id)

    %{leader: leader, player: player, party: party}
  end
end
