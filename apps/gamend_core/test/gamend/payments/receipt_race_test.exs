defmodule Gamend.Payments.ReceiptRaceTest do
  @moduledoc """
  Store receipts validated together: two accounts sending two renewals of one
  subscription, and one account sending one receipt twice.

  A validation checks whether the receipt (or its subscription) is held, asks
  the `before_purchase` hook, then inserts. The hook here holds every
  validation until all of them have passed the check, so the interleaving
  happens on every run and on both adapters: before the claim was decided
  under the receipt's lock, both accounts were fulfilled.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Product
  alias Gamend.Payments.Purchase

  defmodule StoreAdapter do
    def validate_purchase(_user, attrs) do
      {:ok,
       %{
         "product_id" => attrs["product_id"],
         "transaction_id" => attrs["transaction_id"],
         "original_transaction_id" => attrs["original_transaction_id"],
         "status" => "completed",
         "environment" => "test",
         "raw_payload" => attrs
       }}
    end
  end

  defmodule BarrierHooks do
    use Gamend.TestSupport.NoopHooks

    # Every validation waits here, past its early check and before its
    # insert, until all of them have arrived. On SQLite the test pool is one
    # connection, which a racer holds throughout, so the others cannot
    # arrive: after a second it goes on alone, and the racers run in turn.
    @impl true
    def before_purchase(_user, product) do
      {counter, expected} = :persistent_term.get({__MODULE__, :barrier})
      :counters.add(counter, 1, 1)
      wait_until(fn -> :counters.get(counter, 1) >= expected end)
      {:ok, product}
    end

    defp wait_until(fun, attempts \\ 100) do
      cond do
        fun.() ->
          :ok

        attempts == 0 ->
          :alone

        true ->
          Process.sleep(10)
          wait_until(fun, attempts - 1)
      end
    end
  end

  setup do
    adapters = Application.get_env(:gamend_core, :payment_provider_adapters)
    hooks = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :payment_provider_adapters, apple: StoreAdapter)
    Application.put_env(:gamend_core, :hooks_module, BarrierHooks)

    on_exit(fn ->
      restore(:payment_provider_adapters, adapters)
      restore(:hooks_module, hooks)
      :persistent_term.erase({BarrierHooks, :barrier})
    end)

    {product, provider_product} = unboxed(&subscription_product/0)

    cleanup(fn ->
      Repo.delete_all(from p in Purchase, where: p.product_id == ^product.id)
      Repo.delete_all(from e in Entitlement, where: e.product_id == ^product.id)
      Repo.delete_all(from p in Product, where: p.id == ^product.id)
    end)

    %{provider_product: provider_product}
  end

  test "two accounts sending renewals of one subscription: one of them holds it", %{
    provider_product: provider_product
  } do
    users = unboxed(fn -> for _ <- 1..2, do: AccountsFixtures.user_fixture() end)
    cleanup_users(users)
    barrier(2)
    original = "orig_#{System.unique_integer([:positive])}"

    results =
      users
      |> Enum.with_index(1)
      |> Enum.map(fn {user, i} ->
        fn ->
          Payments.validate_store_purchase(user, "apple", %{
            "product_id" => provider_product.external_id,
            "transaction_id" => "#{original}_renewal_#{i}",
            "original_transaction_id" => original
          })
        end
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.count(results, &match?({:ok, %{seen_before: false}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :receipt_already_used})) == 1

    holders =
      unboxed(fn ->
        Repo.all(
          from p in Purchase,
            where: p.provider_original_transaction_id == ^original,
            distinct: true,
            select: p.user_id
        )
      end)

    assert length(holders) == 1, "the subscription is held by #{length(holders)} accounts"

    entitled =
      unboxed(fn ->
        Repo.all(
          from e in Entitlement,
            where: e.user_id in ^Enum.map(users, & &1.id) and e.status == "active",
            select: e.user_id
        )
      end)

    assert entitled == holders
  end

  test "one receipt sent twice at once: one purchase, the other answered as seen", %{
    provider_product: provider_product
  } do
    user = unboxed(fn -> AccountsFixtures.user_fixture() end)
    cleanup_users([user])
    barrier(2)
    transaction = "tx_#{System.unique_integer([:positive])}"

    attrs = %{
      "product_id" => provider_product.external_id,
      "transaction_id" => transaction,
      "original_transaction_id" => transaction
    }

    results = race(2, fn _ -> Payments.validate_store_purchase(user, "apple", attrs) end)

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.count(results, &match?({:ok, %{seen_before: false}}, &1)) == 1
    assert Enum.count(results, &match?({:ok, %{seen_before: true}}, &1)) == 1

    assert unboxed(fn ->
             Repo.aggregate(
               from(p in Purchase, where: p.provider_transaction_id == ^transaction),
               :count
             )
           end) == 1
  end

  defp barrier(expected) do
    :persistent_term.put({BarrierHooks, :barrier}, {:counters.new(1, []), expected})
  end

  defp cleanup_users(users) do
    ids = Enum.map(users, & &1.id)

    cleanup(fn ->
      Repo.delete_all(from p in Purchase, where: p.user_id in ^ids)
      Repo.delete_all(from u in User, where: u.id in ^ids)
    end)
  end

  defp subscription_product do
    suffix = System.unique_integer([:positive])

    {:ok, product} =
      Payments.create_product(%{
        "sku" => "race_premium_#{suffix}",
        "title" => "Premium",
        "kind" => "subscription",
        "grant_config" => %{"entitlement_key" => "race_premium_#{suffix}"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "apple",
        "external_id" => "race_premium_#{suffix}",
        "currency" => "USD",
        "unit_amount" => 499
      })

    {product, provider_product}
  end

  defp restore(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore(key, value), do: Application.put_env(:gamend_core, key, value)
end
