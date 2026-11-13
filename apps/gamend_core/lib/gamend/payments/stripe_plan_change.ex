defmodule Gamend.Payments.StripePlanChange do
  @moduledoc """
  Moving a running Stripe subscription to another product of the same period:
  a hosted server's size, a tier of a monthly plan. Not a longer plan
  (monthly to yearly), which is a new checkout (`Gamend.Payments.Upgrades`).

  `change_stripe_subscription/4` moves the subscription's one item to the new
  product's price (`Providers.Stripe.change_subscription_price/4`), prorated
  and invoiced at once: a dearer product is charged its difference for the
  rest of the period now, a cheaper one leaves a credit on the customer's
  balance for the next invoices. When that invoice cannot be paid, Stripe
  refuses and nothing changes. `end_trial: true` ends a trial now, so the new
  product is charged in full from today: a host's free period may cover one
  product and not another.

  The purchase is then the new product's: its `product_id` and
  `provider_product_id` move, and its entitlement row moves to the new
  product's key (`Payments.entitlement_key/2`, with the purchase's subject),
  keeping its period, so the row a renewal or a refund later finds by
  `source_purchase_id` is the one the buyer now holds. A row already under
  that key is a leftover of an older purchase and is deleted, unless it is
  live through another purchase, which refuses the change
  (`:already_owned`). Each change is listed on the purchase
  (`metadata["plan_changes"]`, newest first) and counted (`payments.subscription.plan_changed`).

  A price changed anywhere else (Stripe's dashboard, its customer portal)
  reaches the purchase the same way, from `customer.subscription.updated`
  (`follow/2`), so Stripe and the rows cannot disagree for longer than a
  webhook, even when the write after a change here failed.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Gamend.Accounts.User
  alias Gamend.Payments
  alias Gamend.Payments.Counters
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.ProviderProduct
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.StripeEvents
  alias Gamend.Repo

  require Gamend.Payments.EntitlementStatus, as: EntitlementStatus
  require Gamend.Payments.ProductKind, as: ProductKind
  require Gamend.Payments.ProviderId, as: ProviderId
  require Gamend.Payments.StripeStatus, as: StripeStatus

  @doc """
  Move the user's subscription behind `entitlement_id` to `target`, an active
  Stripe price of another subscription product with the same period, the
  same currency and the same `per_subject`. Options: `end_trial: true`.

  Refuses with core's `get_user_subscription_entitlement/2` errors,
  `:not_for_sale` (an inactive or non-Stripe price), `:same_product`,
  `:incompatible_product`, `:already_owned`, `:subscription_not_active`
  (only `active` and `trialing` change) and `:several_items`; Stripe's
  refusal, a card declined among them, as `{:stripe_error, error}`.
  """
  @spec change_stripe_subscription(User.t(), Ecto.UUID.t(), ProviderProduct.t(), keyword()) ::
          {:ok,
           %{purchase: Purchase.t(), entitlement: Entitlement.t(), stripe_subscription: map()}}
          | {:error, term()}
  def change_stripe_subscription(
        %User{} = user,
        entitlement_id,
        %ProviderProduct{} = target,
        opts \\ []
      )
      when is_binary(entitlement_id) do
    target = Repo.preload(target, :product)
    adapter = Payments.stripe_adapter()

    with {:ok, entitlement} <- Payments.get_user_subscription_entitlement(user, entitlement_id),
         %Purchase{} = purchase <- entitlement.source_purchase,
         :ok <- changeable(purchase, target),
         :ok <- key_free(purchase, target.product),
         {:ok, subscription_id} <- StripeEvents.stripe_subscription_id(purchase),
         {:ok, current} <- adapter.retrieve_subscription(subscription_id),
         current = Params.normalize(current),
         :ok <- running(current),
         {:ok, item_id} <- single_item_id(current),
         {:ok, subscription} <-
           adapter.change_subscription_price(subscription_id, item_id, target.external_id,
             end_trial: opts[:end_trial] == true,
             idempotency_key: idempotency_key(purchase)
           ),
         subscription = Params.normalize(subscription),
         {:ok, updated, entitlements} <-
           StripeEvents.sync_stripe_subscription(purchase, subscription, "plan_changed") do
      {:ok,
       %{
         purchase: updated,
         entitlement: Enum.find(entitlements, &(&1.id == entitlement.id)),
         stripe_subscription: subscription
       }}
    end
  end

  @doc """
  The purchase brought to the price `subscription` (a Stripe subscription
  object) now bills: unchanged when it is the purchase's own, unknown here, or
  of a product a plan change cannot move to. Called on every subscription
  write (`StripeEvents.sync_stripe_subscription/3`), before its period is
  copied.
  """
  @spec follow(Purchase.t(), map()) :: {:ok, Purchase.t()} | {:error, term()}
  def follow(%Purchase{} = purchase, subscription) when is_map(subscription) do
    purchase = Payments.preload_purchase(purchase)

    case item_price_id(subscription) do
      nil ->
        {:ok, purchase}

      price_id ->
        if match?(%ProviderProduct{external_id: ^price_id}, purchase.provider_product),
          do: {:ok, purchase},
          else: follow_price(purchase, price_id)
    end
  end

  defp follow_price(purchase, price_id) do
    with %ProviderProduct{} = target <-
           Payments.get_provider_product(ProviderId.stripe(), price_id),
         :ok <- followable(purchase, target.product) do
      move(purchase, target)
    else
      nil ->
        Logger.warning(
          "Stripe subscription bills an unknown price price_id=#{price_id} purchase_id=#{purchase.id}"
        )

        {:ok, purchase}

      {:error, reason} ->
        Logger.warning(
          "Stripe subscription moved to a price it cannot follow price_id=#{price_id} " <>
            "purchase_id=#{purchase.id} reason=#{inspect(reason)}"
        )

        {:ok, purchase}
    end
  end

  # ── Checks ──────────────────────────────────────────────────────────────

  defp changeable(%Purchase{product: %Product{} = from} = purchase, %ProviderProduct{} = target) do
    cond do
      target.provider != ProviderId.stripe() or not target.active -> {:error, :not_for_sale}
      target.product_id == from.id -> {:error, :same_product}
      period(target.product) != period(from) -> {:error, :incompatible_product}
      not same_currency?(purchase.provider_product, target) -> {:error, :incompatible_product}
      true -> followable(purchase, target.product)
    end
  end

  defp followable(%Purchase{product: %Product{} = from}, %Product{} = to) do
    if to.kind == ProductKind.subscription() and from.kind == ProductKind.subscription() and
         Payments.per_subject?(to) == Payments.per_subject?(from),
       do: :ok,
       else: {:error, :incompatible_product}
  end

  defp period(%Product{grant_config: config}), do: (config || %{})["duration_seconds"]

  defp same_currency?(%ProviderProduct{currency: from}, %ProviderProduct{currency: to})
       when is_binary(from) and is_binary(to),
       do: String.downcase(from) == String.downcase(to)

  defp same_currency?(_from, _to), do: true

  defp key_free(%Purchase{} = purchase, %Product{} = to) do
    case Payments.get_user_entitlement_by_key(purchase.user_id, new_key(purchase, to)) do
      %Entitlement{source_purchase_id: id} = row when id != purchase.id ->
        if live?(row), do: {:error, :already_owned}, else: :ok

      _free ->
        :ok
    end
  end

  defp live?(%Entitlement{status: EntitlementStatus.active(), expires_at: nil}), do: true

  defp live?(%Entitlement{status: EntitlementStatus.active(), expires_at: at}),
    do: DateTime.compare(at, DateTime.utc_now()) == :gt

  defp live?(_row), do: false

  defp running(%{"status" => status})
       when status in [EntitlementStatus.active(), StripeStatus.trialing()], do: :ok

  defp running(_subscription), do: {:error, :subscription_not_active}

  defp single_item_id(%{"items" => %{"data" => [%{"id" => id}]}}) when is_binary(id),
    do: {:ok, id}

  defp single_item_id(_subscription), do: {:error, :several_items}

  defp item_price_id(%{"items" => %{"data" => [item]}}) do
    case item do
      %{"price" => %{"id" => id}} when is_binary(id) -> id
      %{"price" => id} when is_binary(id) -> id
      %{"plan" => %{"id" => id}} when is_binary(id) -> id
      _none -> nil
    end
  end

  defp item_price_id(_subscription), do: nil

  # The nth change of a purchase: a retry of it answers Stripe's first
  # result, while changing back and forth makes a key of its own each time.
  defp idempotency_key(%Purchase{} = purchase),
    do: "plan-change:#{purchase.id}:#{length(changes(purchase))}"

  defp changes(%Purchase{metadata: %{"plan_changes" => changes}}) when is_list(changes),
    do: changes

  defp changes(_purchase), do: []

  defp new_key(%Purchase{metadata: metadata}, %Product{} = to),
    do: Payments.entitlement_key(to, Payments.subject(metadata))

  # ── Moving the rows ─────────────────────────────────────────────────────

  defp move(%Purchase{} = purchase, %ProviderProduct{product: %Product{} = to} = target) do
    from_key = Payments.purchase_entitlement_key(purchase)
    to_key = new_key(purchase, to)

    change = %{
      "from" => purchase.product.sku,
      "to" => to.sku,
      "price" => target.external_id,
      "at" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
    }

    # Both keys' rows locked (`Payments.with_entitlement_locks/3`): the move
    # reads and rewrites them, and a grant to either would otherwise land
    # between.
    Payments.with_entitlement_locks(purchase.user_id, [from_key, to_key], fn ->
      with :ok <- clear_key(purchase, from_key, to_key),
           {:ok, moved} <-
             purchase
             |> Purchase.changeset(%{
               product_id: to.id,
               provider_product_id: target.id,
               metadata:
                 Map.put(purchase.metadata || %{}, "plan_changes", [change | changes(purchase)])
             })
             |> Repo.update(),
           :ok <- rekey(purchase, from_key, to_key, to) do
        Repo.preload(moved, [:product, :provider_product], force: true)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, moved} ->
        Logger.info(
          "Stripe subscription plan_changed purchase_id=#{purchase.id} " <>
            "user_id=#{purchase.user_id} from=#{change["from"]} to=#{change["to"]}"
        )

        Counters.count("subscription.plan_changed", sku: to.sku)
        Payments.tap_bump({:ok, moved}, {:payments, :purchase_version})

      {:error, :already_owned} ->
        Logger.warning(
          "Stripe subscription moved to a key held through another purchase " <>
            "purchase_id=#{purchase.id} key=#{to_key}"
        )

        {:ok, purchase}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clear_key(_purchase, key, key), do: :ok

  defp clear_key(%Purchase{} = purchase, _from_key, to_key) do
    case Payments.get_user_entitlement_by_key(purchase.user_id, to_key) do
      nil ->
        :ok

      %Entitlement{source_purchase_id: id} = row when id == purchase.id ->
        delete(row)

      row ->
        if live?(row), do: {:error, :already_owned}, else: delete(row)
    end
  end

  defp delete(%Entitlement{} = row) do
    case Repo.delete(row) do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp rekey(%Purchase{} = purchase, from_key, to_key, %Product{} = to) do
    from(e in Entitlement, where: e.source_purchase_id == ^purchase.id and e.key == ^from_key)
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn row, :ok ->
      row
      |> Entitlement.changeset(%{
        key: to_key,
        product_id: to.id,
        metadata: Map.put(row.metadata || %{}, "product_sku", to.sku)
      })
      |> Repo.update()
      |> case do
        {:ok, _row} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
