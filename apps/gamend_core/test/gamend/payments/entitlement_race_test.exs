defmodule Gamend.Payments.EntitlementRaceTest do
  @moduledoc """
  One `(user, key)` entitlement row written by several callers at once:
  grants of different lengths, and two purchases of the key fulfilled
  together.

  Each read the row with no lock on it, so the last writer won (a grant could
  shorten what another gave), and a second insert failed the unique index (a
  paid purchase rolled back and stayed pending). Postgres only shows it; see
  `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Product
  alias Gamend.Payments.Purchase

  @users 10

  defmodule Hooks do
    use Gamend.TestSupport.NoopHooks
  end

  setup do
    hooks = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, Hooks)

    on_exit(fn ->
      if hooks,
        do: Application.put_env(:gamend_core, :hooks_module, hooks),
        else: Application.delete_env(:gamend_core, :hooks_module)
    end)

    users = unboxed(fn -> for _ <- 1..@users, do: AccountsFixtures.user_fixture() end)
    ids = Enum.map(users, & &1.id)
    {product, provider_product} = unboxed(&entitlement_product/0)

    cleanup(fn ->
      Repo.delete_all(from p in Purchase, where: p.user_id in ^ids)
      Repo.delete_all(from u in User, where: u.id in ^ids)
      Repo.delete_all(from p in Product, where: p.id == ^product.id)
    end)

    %{users: users, product: product, provider_product: provider_product}
  end

  test "grants at once never shorten one another, and none fails", %{users: users} do
    now = DateTime.utc_now(:second)
    lengths = [7, 365, 30, 90]

    results =
      users
      |> Enum.flat_map(fn user ->
        for days <- lengths do
          fn ->
            Payments.grant_entitlement(user.id, "race_grant",
              expires_at: DateTime.add(now, days, :day)
            )
          end
        end
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.all?(results, &match?({:ok, %Entitlement{}}, &1)), inspect(results)

    for user <- users do
      [row] = unboxed(fn -> Repo.all(entitlement_rows(user.id, "race_grant")) end)
      assert row.expires_at == DateTime.add(now, 365, :day), "a grant shortened another"
    end
  end

  test "extends at once each add their days", %{users: users} do
    now = DateTime.utc_now(:second)
    ends_at = DateTime.add(now, 10, :day)

    rows =
      unboxed(fn ->
        for user <- users do
          {:ok, row} = Payments.grant_entitlement(user.id, "race_extend", expires_at: ends_at)
          row
        end
      end)

    results =
      rows
      |> Enum.flat_map(fn row ->
        for _ <- 1..3, do: fn -> Payments.extend_entitlement(row.id, 30) end
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)
    assert Enum.all?(results, &match?({:ok, %Entitlement{}}, &1)), inspect(results)

    for user <- users do
      [row] = unboxed(fn -> Repo.all(entitlement_rows(user.id, "race_extend")) end)
      assert row.expires_at == DateTime.add(ends_at, 90, :day), "an extend lost another's days"
    end
  end

  test "two purchases of one key fulfilled at once both complete", %{
    users: users,
    provider_product: provider_product
  } do
    purchases =
      unboxed(fn ->
        for user <- users, n <- 1..2 do
          {:ok, purchase} =
            Payments.create_purchase(user, provider_product, %{
              "provider_transaction_id" => "race_#{user.id}_#{n}"
            })

          purchase
        end
      end)

    results = race(Enum.map(purchases, fn p -> fn -> Payments.fulfill_purchase(p) end end))

    refute Enum.any?(results, &match?({:raised, _}, &1)), inspect(results)

    assert Enum.all?(results, &match?({:ok, %Purchase{status: "completed"}}, &1)),
           inspect(results)

    for user <- users do
      assert [%Entitlement{status: "active"}] =
               unboxed(fn -> Repo.all(entitlement_rows(user.id, "race_pass")) end)
    end
  end

  defp entitlement_rows(user_id, key),
    do: from(e in Entitlement, where: e.user_id == ^user_id and e.key == ^key)

  defp entitlement_product do
    suffix = System.unique_integer([:positive])

    {:ok, product} =
      Payments.create_product(%{
        "sku" => "race_pass_#{suffix}",
        "title" => "Pass",
        "kind" => "entitlement",
        "grant_config" => %{"entitlement_key" => "race_pass"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_race_pass_#{suffix}",
        "currency" => "USD",
        "unit_amount" => 999
      })

    {product, provider_product}
  end
end
