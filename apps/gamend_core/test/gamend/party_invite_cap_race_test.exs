defmodule Gamend.PartyInviteCapRaceTest do
  @moduledoc """
  Leaders of several parties inviting one player at once, past
  `max_party_pending_invites`. The cap is the recipient's, and it was counted
  and then inserted under no lock at all, so each invite counted the others
  as not there yet.

  Postgres shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Parties
  alias Gamend.Parties.Party
  alias Gamend.Parties.PartyInvite

  setup do
    previous = Application.get_env(:gamend_core, Gamend.Limits, [])
    Gamend.SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_party_pending_invites, 2)
    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)
  end

  test "invites from many leaders at once end at the recipient's cap" do
    {player, leaders} =
      unboxed(fn ->
        player = AccountsFixtures.user_fixture()

        leaders =
          for _ <- 1..6 do
            leader = AccountsFixtures.user_fixture()
            :ok = AccountsFixtures.befriend(leader, player)
            {:ok, _party} = Parties.create_party(leader, %{})
            leader
          end

        {player, leaders}
      end)

    user_ids = [player.id | Enum.map(leaders, & &1.id)]

    cleanup(fn ->
      Repo.update_all(from(u in User, where: u.id in ^user_ids), set: [party_id: nil])
      Repo.delete_all(from p in Party, where: p.leader_id in ^user_ids)
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)

    results =
      race(
        Enum.map(leaders, fn leader -> fn -> Parties.invite_to_party(leader, player.id) end end)
      )

    refute Enum.any?(results, &match?({:raised, _}, &1)), "raised: #{inspect(results)}"
    assert Enum.count(results, &match?({:ok, %PartyInvite{}}, &1)) == 2
    assert Enum.count(results, &match?({:error, :too_many_pending_invites}, &1)) == 4

    pending =
      unboxed(fn ->
        Repo.aggregate(
          from(i in PartyInvite, where: i.recipient_id == ^player.id and i.status == "pending"),
          :count
        )
      end)

    assert pending == 2
  end
end
