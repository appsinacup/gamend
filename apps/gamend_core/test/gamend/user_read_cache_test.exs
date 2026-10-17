defmodule Gamend.UserReadCacheTest do
  @moduledoc """
  The per-user reads a page makes on every render — wallet balances, the
  entitlements behind a paid plan, KV rows that are not there — come from
  `Gamend.Cache`: one query fills them, and the writes that change them evict
  them. Each was a query per call, and a page made several of the same one.

  The app cache runs in bypass mode during tests, so this module points the
  calling process at a real instance, as `Gamend.QuestsDoneMarkerTest` does.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Cache
  alias Gamend.Economy
  alias Gamend.KV
  alias Gamend.Payments

  setup do
    name = :"user_read_cache_#{System.unique_integer([:positive])}"
    l1 = :"#{name}_l1"

    start_supervised!(
      {Cache,
       name: name,
       bypass_mode: false,
       inclusion_policy: :inclusive,
       levels: [{Cache.L1, [name: l1]}]}
    )

    _ = Cache.put_dynamic_cache(name)

    %{user: AccountsFixtures.user_fixture()}
  end

  describe "wallet balances" do
    test "every currency comes from one query, until a change", %{user: user} do
      {:ok, 100} = Economy.grant(user.id, "coins", 100)
      {:ok, 5} = Economy.grant(user.id, "gems", 5)

      {reads, count} =
        queries("wallets", fn ->
          {Economy.balance(user.id, "coins"), Economy.balance(user.id, "gems"),
           Economy.balances(user.id)}
        end)

      assert reads == {100, 5, %{"coins" => 100, "gems" => 5}}
      assert count == 1
    end

    test "a spend and a grant are read back at once", %{user: user} do
      {:ok, 100} = Economy.grant(user.id, "coins", 100)
      assert Economy.balance(user.id, "coins") == 100

      {:ok, 70} = Economy.spend(user.id, "coins", 30)
      assert Economy.balance(user.id, "coins") == 70

      {:ok, 80} = Economy.grant(user.id, "coins", 10)
      assert Economy.balances(user.id) == %{"coins" => 80}
    end

    test "a currency with no wallet reads as zero", %{user: user} do
      assert Economy.balance(user.id, "coins") == 0
    end
  end

  describe "entitlements" do
    test "any number of keys come from one query", %{user: user} do
      {_, count} =
        queries("entitlements", fn ->
          refute Payments.has_entitlement?(user.id, "pro")
          refute Payments.has_entitlement?(user.id, "pro_trial")
          refute Payments.entitlement_ever?(user.id, "pro_trial")
        end)

      assert count == 1
    end

    test "a grant counts at once, and its end is kept while cached", %{user: user} do
      refute Payments.has_entitlement?(user.id, "pro")

      ends = DateTime.add(DateTime.utc_now(:second), 1, :second)
      {:ok, _} = Payments.grant_entitlement(user.id, "pro", expires_at: ends)
      assert Payments.has_entitlement?(user.id, "pro")

      # Decided against the clock at read time: the cached row stops counting
      # when it ends, with no write to evict it.
      Process.sleep(1_100)

      {_, count} =
        queries("entitlements", fn ->
          refute Payments.has_entitlement?(user.id, "pro")
          assert Payments.entitlement_ever?(user.id, "pro")
        end)

      assert count == 0
    end
  end

  describe "KV rows that are not there" do
    test "are remembered until the key is written", %{user: user} do
      assert KV.get("read_cache_probe", user_id: user.id) == :error

      {_, count} =
        queries("kv_entries", fn ->
          assert KV.get("read_cache_probe", user_id: user.id) == :error
        end)

      assert count == 0

      {:ok, _} = KV.put("read_cache_probe", %{"n" => 1}, %{}, user_id: user.id)

      # The writer reads its own write straight back — a read-modify-write
      # whose first read found nothing must not be answered "nothing" again.
      assert {:ok, %{value: %{"n" => 1}}} = KV.get("read_cache_probe", user_id: user.id)

      :ok = KV.delete("read_cache_probe", user_id: user.id)
      assert KV.get("read_cache_probe", user_id: user.id) == :error
    end

    test "are not remembered inside a transaction", %{user: user} do
      {:ok, :error} =
        Repo.transaction(fn -> KV.get("read_cache_probe_tx", user_id: user.id) end)

      {_, count} =
        queries("kv_entries", fn ->
          assert KV.get("read_cache_probe_tx", user_id: user.id) == :error
        end)

      assert count == 1
    end
  end

  # How many queries on `source` this process sends while `fun` runs.
  defp queries(source, fun) do
    ref = make_ref()
    handler = "user-read-cache-#{inspect(ref)}"

    # The event `Gamend.Repo.SlowLog` listens on too.
    :ok =
      :telemetry.attach(
        handler,
        [:gamend, :repo, :query],
        &__MODULE__.count_query/4,
        {self(), ref, source}
      )

    try do
      result = fun.()
      {result, drain(ref, 0)}
    after
      :telemetry.detach(handler)
    end
  end

  @doc false
  def count_query(_event, _measurements, metadata, {pid, ref, source}) do
    if self() == pid and metadata[:source] == source, do: send(pid, {ref, :query})
  end

  defp drain(ref, count) do
    receive do
      {^ref, :query} -> drain(ref, count + 1)
    after
      0 -> count
    end
  end
end
