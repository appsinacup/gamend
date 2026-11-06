defmodule Gamend.Payments.RevokeRaceTest do
  @moduledoc """
  One refund reaching the server as several events at once
  (`charge.refunded`, `refund.created`, `refund.updated`).

  Each revoked the purchase again, whatever it already was, so
  `after_purchase_revoked` ran once per event: a host taking the bought
  coins back on it took them three times. The revocation is now a
  transition decided on the locked row, and only the event that makes it
  runs the hook. The repeat shows on both adapters; the overlap on Postgres.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Product
  alias Gamend.Payments.Purchase

  @users 10

  defmodule RevokeHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def after_purchase_revoked(purchase) do
      send(:persistent_term.get({__MODULE__, :pid}), {:revoked, purchase.id})
      :ok
    end
  end

  setup do
    :persistent_term.put({RevokeHooks, :pid}, self())
    hooks = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, RevokeHooks)

    on_exit(fn ->
      if hooks,
        do: Application.put_env(:gamend_core, :hooks_module, hooks),
        else: Application.delete_env(:gamend_core, :hooks_module)

      :persistent_term.erase({RevokeHooks, :pid})
    end)

    users = unboxed(fn -> for _ <- 1..@users, do: AccountsFixtures.user_fixture() end)
    ids = Enum.map(users, & &1.id)
    {product, provider_product} = unboxed(&entitlement_product/0)

    cleanup(fn ->
      Repo.delete_all(from p in Purchase, where: p.user_id in ^ids)
      Repo.delete_all(from u in User, where: u.id in ^ids)
      Repo.delete_all(from p in Product, where: p.id == ^product.id)
    end)

    %{users: users, provider_product: provider_product}
  end

  test "reversal events at once end a purchase once", %{
    users: users,
    provider_product: provider_product
  } do
    purchases =
      unboxed(fn ->
        for user <- users do
          {:ok, purchase} =
            Payments.create_purchase(user, provider_product, %{
              "provider_transaction_id" => "race_refund_#{user.id}"
            })

          {:ok, purchase} = Payments.fulfill_purchase(purchase)
          purchase
        end
      end)

    results =
      purchases
      |> Enum.flat_map(fn purchase ->
        for event <- ~w(charge.refunded refund.created refund.updated) do
          fn ->
            Payments.revoke_purchase(purchase, %{"status" => "refunded", "reason" => event})
          end
        end
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.all?(results, &match?({:ok, %Purchase{status: "refunded"}}, &1))

    revoked = collect_revoked([])

    for purchase <- purchases do
      runs = Enum.count(revoked, &(&1 == purchase.id))
      assert runs == 1, "after_purchase_revoked ran #{runs} times"
    end
  end

  defp collect_revoked(acc) do
    receive do
      {:revoked, id} -> collect_revoked([id | acc])
    after
      500 -> acc
    end
  end

  defp entitlement_product do
    suffix = System.unique_integer([:positive])

    {:ok, product} =
      Payments.create_product(%{
        "sku" => "race_refund_#{suffix}",
        "title" => "Pass",
        "kind" => "entitlement",
        "grant_config" => %{"entitlement_key" => "race_refund"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_race_refund_#{suffix}",
        "currency" => "USD",
        "unit_amount" => 999
      })

    {product, provider_product}
  end
end
