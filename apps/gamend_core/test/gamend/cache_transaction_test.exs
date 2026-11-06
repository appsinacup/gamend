defmodule Gamend.CacheTransactionTest do
  @moduledoc """
  A read inside a transaction is usually deciding a write, so
  `Gamend.Cache.cached/3` answers it from the database there, never from a
  copy up to a TTL old. `Accounts.get_user/1` gating a seat once read a
  `lobby_id` another request had already set.

  The app cache runs in bypass mode during tests, so this points the process
  at a real instance, as `Gamend.CacheFillRaceTest` does.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Cache

  setup do
    name = :"cache_transaction_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Cache,
       name: name,
       bypass_mode: false,
       inclusion_policy: :inclusive,
       levels: [{Cache.L1, [name: :"#{name}_l1"]}]}
    )

    _ = Cache.put_dynamic_cache(name)
    :ok
  end

  test "a cached read inside a transaction reads the database" do
    user = AccountsFixtures.user_fixture()
    Accounts.cache_user(%{user | display_name: "Stale copy"})

    assert Accounts.get_user(user.id).display_name == "Stale copy",
           "outside a transaction the cache answers"

    {:ok, inside} = Repo.transaction(fn -> Accounts.get_user(user.id) end)
    assert inside.display_name == user.display_name
  end

  test "a read inside a transaction does not fill the cache" do
    calls = :counters.new(1, [])

    read = fn ->
      Cache.cached({:cache_transaction_test, :key}, [ttl: 60_000], fn ->
        :counters.add(calls, 1, 1)
        :value
      end)
    end

    {:ok, :value} = Repo.transaction(read)
    assert read.() == :value
    assert read.() == :value
    assert :counters.get(calls, 1) == 2, "the transaction's read was not cached; the next one was"
  end
end
