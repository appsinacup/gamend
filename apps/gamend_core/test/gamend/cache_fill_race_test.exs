defmodule Gamend.CacheFillRaceTest do
  @moduledoc """
  A read that misses the cache queries the row and then caches it. A write
  that lands between the two evicts a key that is not there yet, and the read
  then caches the row as it was before the write, until the TTL: a revoked
  token still accepted, a balance or a KV value from before the change, and a
  read-modify-write under a lock that starts from it and writes the old row
  back.

  Each test stops a reader between its query and its cache put (a
  `[:gamend, :repo, :query]` handler that waits in the reader's own process),
  writes, lets the reader finish, and asks what the cache answers.

  The app cache runs in bypass mode during tests, so each process here is
  pointed at a real instance, as `Gamend.UserReadCacheTest` does.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Cache
  alias Gamend.Economy
  alias Gamend.KV

  setup do
    name = :"cache_fill_race_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Cache,
       name: name,
       bypass_mode: false,
       inclusion_policy: :inclusive,
       levels: [{Cache.L1, [name: :"#{name}_l1"]}]}
    )

    _ = Cache.put_dynamic_cache(name)

    handler = "cache-fill-race-#{name}"
    :ok = :telemetry.attach(handler, [:gamend, :repo, :query], &__MODULE__.pause/4, nil)
    on_exit(fn -> :telemetry.detach(handler) end)

    %{cache: name}
  end

  test "a KV read that started before a write does not cache the old value", %{cache: cache} do
    {:ok, _} = KV.put("race", %{"n" => 1})
    _ = Cache.delete({:kv, :global, "race"})

    reader = paused(cache, "kv_entries", fn -> KV.get("race") end)
    {:ok, _} = KV.put("race", %{"n" => 2})

    assert {:ok, %{value: %{"n" => 1}}} = resume(reader)
    assert {:ok, %{value: %{"n" => 2}}} = KV.get("race")
  end

  test "a KV write that lands first is not overwritten in the cache by an earlier one",
       %{cache: cache} do
    {:ok, _} = KV.put("race", %{"n" => 1})

    # Stopped after its insert, before it touches the cache.
    earlier = paused(cache, "kv_entries", fn -> KV.put("race", %{"n" => 2}) end)
    {:ok, _} = KV.put("race", %{"n" => 3})
    {:ok, _} = resume(earlier)

    assert {:ok, %{value: %{"n" => 3}}} = KV.get("race")
  end

  test "a KV read of a missing key does not cache the absence over a write", %{cache: cache} do
    reader = paused(cache, "kv_entries", fn -> KV.get("race") end)
    {:ok, _} = KV.put("race", %{"n" => 1})

    assert :error = resume(reader)
    assert {:ok, %{value: %{"n" => 1}}} = KV.get("race")
  end

  test "revoking a user's tokens is not undone by an auth read in flight", %{cache: cache} do
    user = AccountsFixtures.user_fixture()
    _ = Cache.delete({:accounts, :user, user.id})

    reader = paused(cache, "users", fn -> Accounts.get_user(user.id) end)
    {:ok, {revoked, _tokens}} = Accounts.revoke_all_tokens(user)

    assert resume(reader).token_version == user.token_version
    assert Accounts.get_user(user.id).token_version == revoked.token_version
  end

  test "a balance read in flight does not cache the balance from before a grant",
       %{cache: cache} do
    user = AccountsFixtures.user_fixture()
    {:ok, 100} = Economy.grant(user.id, "coins", 100)
    _ = Cache.delete({:economy, :balances, user.id})

    reader = paused(cache, "wallets", fn -> Economy.balances(user.id) end)
    {:ok, 150} = Economy.grant(user.id, "coins", 50)

    assert resume(reader) == %{"coins" => 100}
    assert Economy.balances(user.id) == %{"coins" => 150}
  end

  # Runs `fun` in its own process, on the test's cache, and returns once it
  # has stopped right after its first query on `source`.
  defp paused(cache, source, fun) do
    test = self()

    task =
      Task.async(fn ->
        _ = Cache.put_dynamic_cache(cache)
        Process.put(:pause_after_query, {test, source})
        fun.()
      end)

    assert_receive {:paused, pid}, 5_000
    {task, pid}
  end

  defp resume({task, pid}) do
    send(pid, :resume)
    Task.await(task, 5_000)
  end

  @doc false
  def pause(_event, _measurements, metadata, _config) do
    source = metadata[:source]

    case Process.get(:pause_after_query) do
      {test, ^source} ->
        Process.delete(:pause_after_query)
        send(test, {:paused, self()})

        receive do
          :resume -> :ok
        end

      _ ->
        :ok
    end
  end
end
