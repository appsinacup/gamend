defmodule Gamend.KVEntryCapRaceTest do
  @moduledoc """
  Creates for one user landing together, one under `max_kv_entries_per_user`.

  `KV.create_entry/1` counted the user's entries (through the cache, and
  outside any lock) and then inserted, so creates landing together all saw
  room for one more and all went in. The count and the insert now run under
  a lock on the user.

  Postgres only shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.KV
  alias Gamend.KV.Entry
  alias Gamend.SettingsHelpers

  @racers 8

  setup do
    previous = SettingsHelpers.get(:gamend_core, Gamend.Limits, :max_kv_entries_per_user)
    SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_kv_entries_per_user, 3)

    on_exit(fn ->
      if previous,
        do: SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_kv_entries_per_user, previous),
        else: SettingsHelpers.delete(:gamend_core, Gamend.Limits, :max_kv_entries_per_user)
    end)

    user =
      unboxed(fn ->
        user = AccountsFixtures.unconfirmed_user_fixture()

        for i <- 1..2 do
          {:ok, _} = KV.create_entry(%{key: "held-#{i}", user_id: user.id, value: %{}})
        end

        user
      end)

    cleanup(fn ->
      Repo.delete_all(from e in Entry, where: e.user_id == ^user.id)
      Repo.delete_all(from u in User, where: u.id == ^user.id)
    end)

    %{user: user}
  end

  test "the last entry under the cap goes to one create", %{user: user} do
    results =
      race(@racers, fn i ->
        KV.create_entry(%{key: "racer-#{i}", user_id: user.id, value: %{"i" => i}})
      end)

    refute Enum.any?(results, &match?({:raised, _}, &1)), "a create raised: #{inspect(results)}"
    assert Enum.count(results, &match?({:ok, %Entry{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :too_many_entries})) == @racers - 1

    held =
      unboxed(fn -> Repo.aggregate(from(e in Entry, where: e.user_id == ^user.id), :count) end)

    assert held == 3
  end
end
