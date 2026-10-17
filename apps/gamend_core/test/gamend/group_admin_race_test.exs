defmodule Gamend.GroupAdminRaceTest do
  @moduledoc """
  Admin changes racing each other in one group. Two admins demoting or
  kicking each other at once must not both land and leave the group with no
  admin, and a kick or promotion racing the target's own leave must answer
  `:not_member`, not raise on a row that is gone.

  `Gamend.MembershipConcurrencyTest` met the raises about twice in a hundred
  runs, amid a random storm of moves; here the moves race each other
  directly, round after round.
  """
  use Gamend.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupMember
  alias Gamend.Repo

  @rounds 25

  setup do
    %{users: for(_ <- 1..3, do: AccountsFixtures.user_fixture())}
  end

  test "two admins demoting each other leave the group with an admin", %{users: [a, b | _]} do
    for _ <- 1..@rounds do
      group_id = group_with_admins([a, b])

      race(
        fn -> Groups.demote_member(a.id, group_id, b.id) end,
        fn -> Groups.demote_member(b.id, group_id, a.id) end
      )

      assert admins(group_id) >= 1
      drop(group_id)
    end
  end

  test "two admins kicking each other leave the group with an admin", %{users: [a, b, c]} do
    for _ <- 1..@rounds do
      group_id = group_with_admins([a, b])
      {:ok, _} = Groups.join_group(c.id, group_id)

      race(
        fn -> Groups.kick_member(a.id, group_id, b.id) end,
        fn -> Groups.kick_member(b.id, group_id, a.id) end
      )

      assert admins(group_id) >= 1
      drop(group_id)
    end
  end

  test "a kick or a promotion racing the target's leave answers, never raises",
       %{users: [a, b | _]} do
    for change <- [&Groups.kick_member/3, &Groups.promote_member/3], _ <- 1..@rounds do
      group_id = group_with_admins([a])
      {:ok, _} = Groups.join_group(b.id, group_id)

      [changed, left] =
        race(fn -> change.(a.id, group_id, b.id) end, fn -> Groups.leave_group(b.id, group_id) end)

      assert match?({:ok, _}, changed) or changed == {:error, :not_member}
      assert match?({:ok, _}, left) or left == {:error, :not_member}
      drop(group_id)
    end
  end

  # Each round's group goes, or the creator soon hits `max_groups_created_per_user`.
  defp drop(group_id) do
    Repo.delete_all(from m in GroupMember, where: m.group_id == ^group_id)
    Repo.delete_all(from g in Group, where: g.id == ^group_id)
  end

  # A group `admins` all administer, the first of them its creator.
  defp group_with_admins([creator | others]) do
    {:ok, group} =
      Groups.create_group(creator.id, %{title: "race-#{System.unique_integer([:positive])}"})

    for admin <- others do
      {:ok, _} = Groups.join_group(admin.id, group.id)
      {:ok, _} = Groups.promote_member(creator.id, group.id, admin.id)
    end

    group.id
  end

  # Both at once; what each answered, in order. On SQLite the group lock is a
  # `:global` mutex, whose waiter backs off by a growing random sleep, so one
  # race now and then takes seconds; the default 5s await failed on that once
  # in sixty runs. A deadlock would still hang past this and fail.
  defp race(first, second) do
    [first, second] |> Enum.map(&Task.async/1) |> Task.await_many(60_000)
  end

  defp admins(group_id) do
    Repo.one(
      from m in GroupMember, where: m.group_id == ^group_id and m.role == "admin", select: count()
    )
  end
end
