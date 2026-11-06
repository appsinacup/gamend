defmodule Gamend.GroupCapRaceTest do
  @moduledoc """
  Per-player caps on groups, with the requests landing together: one player
  joining several public groups past `max_groups_per_user`, one player
  creating groups past `max_groups_created_per_user`, and admins of several
  groups inviting one player past `max_group_pending_invites`.

  Each counted and then inserted under a lock on the group, or under no lock
  at all, so writes for one player in different groups never waited on each
  other and each counted the others as not there yet.

  Postgres shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupInvite
  alias Gamend.Groups.GroupMember

  setup do
    previous = Application.get_env(:gamend_core, Gamend.Limits, [])

    Application.put_env(
      :gamend_core,
      Gamend.Limits,
      Keyword.merge(previous,
        max_groups_per_user: 2,
        max_groups_created_per_user: 2,
        max_group_pending_invites: 2
      )
    )

    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)
  end

  test "a player joining many groups at once ends at the cap" do
    {player, groups} =
      unboxed(fn ->
        player = AccountsFixtures.user_fixture()

        groups =
          for i <- 1..6 do
            owner = AccountsFixtures.user_fixture()

            {:ok, g} =
              Groups.create_group(owner.id, %{"title" => "Open #{i}", "type" => "public"})

            g
          end

        {player, groups}
      end)

    track([player.id | Enum.map(groups, & &1.creator_id)], Enum.map(groups, & &1.id))

    results = race(Enum.map(groups, fn g -> fn -> Groups.join_group(player.id, g.id) end end))

    refute Enum.any?(results, &match?({:raised, _}, &1)), "raised: #{inspect(results)}"
    assert Enum.count(results, &match?({:ok, _}, &1)) == 2
    assert Enum.count(results, &match?({:error, :too_many_groups}, &1)) == 4
    assert memberships(player.id) == 2
  end

  test "a player creating many groups at once ends at the cap" do
    player = unboxed(fn -> AccountsFixtures.user_fixture() end)
    track([player.id], [])
    cleanup(fn -> Repo.delete_all(from g in Group, where: g.creator_id == ^player.id) end)

    results =
      race(6, fn i -> Groups.create_group(player.id, %{"title" => "Mine #{i}"}) end)

    refute Enum.any?(results, &match?({:raised, _}, &1)), "raised: #{inspect(results)}"
    assert Enum.count(results, &match?({:ok, _}, &1)) == 2
    assert Enum.count(results, &match?({:error, :too_many_groups_created}, &1)) == 4
  end

  test "admins of many groups inviting one player at once end at the cap" do
    {player, groups} =
      unboxed(fn ->
        player = AccountsFixtures.user_fixture()

        groups =
          for i <- 1..6 do
            admin = AccountsFixtures.user_fixture()
            :ok = AccountsFixtures.befriend(admin, player)

            {:ok, g} =
              Groups.create_group(admin.id, %{"title" => "Crew #{i}", "type" => "private"})

            g
          end

        {player, groups}
      end)

    track([player.id | Enum.map(groups, & &1.creator_id)], Enum.map(groups, & &1.id))

    results =
      race(
        Enum.map(groups, fn g ->
          fn -> Groups.invite_to_group(g.creator_id, g.id, player.id) end
        end)
      )

    refute Enum.any?(results, &match?({:raised, _}, &1)), "raised: #{inspect(results)}"
    assert Enum.count(results, &match?({:ok, %GroupInvite{}}, &1)) == 2
    assert Enum.count(results, &match?({:error, :too_many_pending_invites}, &1)) == 4

    pending =
      unboxed(fn ->
        Repo.aggregate(
          from(i in GroupInvite, where: i.recipient_id == ^player.id and i.status == "pending"),
          :count
        )
      end)

    assert pending == 2
  end

  # Groups first (their creator is only nilified), then the users, which
  # take memberships, invites and friendships with them.
  defp track(user_ids, group_ids) do
    cleanup(fn ->
      Repo.delete_all(from g in Group, where: g.id in ^group_ids)
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)
  end

  defp memberships(user_id) do
    unboxed(fn ->
      Repo.aggregate(from(m in GroupMember, where: m.user_id == ^user_id), :count)
    end)
  end
end
