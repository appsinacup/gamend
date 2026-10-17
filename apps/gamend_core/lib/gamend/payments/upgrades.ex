defmodule Gamend.Payments.Upgrades do
  @moduledoc """
  Moving to a longer plan: a monthly subscription to a yearly one, or any
  subscription to a one-off purchase (lifetime) of the same entitlement.

  An entitlement is one row per user and key, so a second purchase of a key
  the user holds is refused (`:already_owned`). An upgrade is the exception
  (`replaced_purchase/2`): the row comes from a Stripe subscription still
  running, and the new product lasts longer (`longer?/2`: a one-off
  entitlement outlasts any subscription, a subscription outlasts a shorter
  one by `grant_config["duration_seconds"]`).

  The new purchase takes the row when it is fulfilled (`grant_purchase`
  upserts by key and moves `source_purchase_id`), so the old subscription's
  later webhooks find no row to change. What is left is the old subscription
  itself, which would go on charging. `supersede/1`, run once a purchase is
  fulfilled, ends it the way the App Store ends an upgraded plan:

    * a subscription that starts when the old one's paid period ends
      (`first_charge_at/2`, the checkout's `trial_end`): the old one is set to
      cancel at its period end. Nothing is paid twice, nothing refunded.
    * anything else (a one-off purchase, or a period ending within 48 hours,
      which Stripe charges at once): the old one is cancelled now and the
      unused part of its last payment refunded, pro rata by time from the
      moment the new purchase was paid. The amount is the same on every
      retry, so the refund's idempotency key holds.

  The refund carries `superseded_purchase_id`, never `purchase_id`: the
  reversal path counts a refund only when it is ours, and this one takes
  nothing back. Progress is kept on the old purchase as
  `metadata["superseded"]` (`by`, `mode`, `requested_at`, then `refund_id`,
  `refund_amount`, `done_at`), written before Stripe is called and after, as
  `StripeRefunds` does. `sweep/1` finishes what a failure left.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Gamend.Lock
  alias Gamend.Payments
  alias Gamend.Payments.Counters
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.StripeEvents
  alias Gamend.Payments.StripeRefunds
  alias Gamend.Repo

  # Stripe refuses a trial ending within 48 hours (`Providers.Stripe` drops one
  # under 48 h 5 min) or more than two years out. Ten minutes over, so the page
  # that names the date and the checkout that sets it agree.
  @min_deferral_seconds 48 * 3600 + 10 * 60
  @max_deferral_seconds 730 * 86_400

  # A new subscription whose first charge lands this close to the old
  # period's end still takes over from it.
  @cover_tolerance_seconds 3600

  @batch 50

  @type mode :: :at_period_end | :now

  @doc """
  The purchase behind the user's active `key` row, with its product, or nil:
  what the user holds that plan by. A grant with no purchase answers nil.
  """
  @spec holding_purchase(Ecto.UUID.t() | nil, String.t()) :: Purchase.t() | nil
  def holding_purchase(user_id, key) when is_binary(user_id) and is_binary(key) do
    case active_row(user_id, key) do
      %Entitlement{source_purchase: %Purchase{} = purchase} -> purchase
      _none -> nil
    end
  end

  def holding_purchase(_user_id, _key), do: nil

  @doc """
  The Stripe subscription a purchase of `product` would replace for the user,
  or nil: the purchase behind their active row for the product's entitlement,
  when it is a running Stripe subscription and `product` lasts longer.
  """
  @spec replaced_purchase(Ecto.UUID.t() | nil, Product.t()) :: Purchase.t() | nil
  def replaced_purchase(user_id, %Product{kind: kind} = product)
      when is_binary(user_id) and kind in ~w(entitlement subscription) do
    with %Purchase{} = purchase <-
           holding_purchase(user_id, Payments.product_entitlement_key(product)),
         true <- running_stripe_subscription?(purchase),
         true <- longer?(product, purchase.product) do
      purchase
    else
      _not_an_upgrade -> nil
    end
  end

  def replaced_purchase(_user_id, _product), do: nil

  @doc "Whether buying `product` would replace a plan the user holds (`replaced_purchase/2`)."
  @spec upgrade?(Ecto.UUID.t() | nil, Product.t()) :: boolean()
  def upgrade?(user_id, product), do: replaced_purchase(user_id, product) != nil

  @doc """
  Whether `new` lasts longer than `old`: a one-off entitlement has no end, a
  subscription lasts its `grant_config["duration_seconds"]`, and a product
  with no period set lasts nothing (it is never an upgrade, nor upgraded
  from, by length).
  """
  @spec longer?(Product.t(), Product.t()) :: boolean()
  def longer?(%Product{} = new, %Product{} = old) do
    case {span(new), span(old)} do
      {:forever, :forever} -> false
      {:forever, _seconds} -> true
      {_seconds, :forever} -> false
      {new_seconds, old_seconds} -> old_seconds > 0 and new_seconds > old_seconds
    end
  end

  defp span(%Product{kind: "entitlement"}), do: :forever

  defp span(%Product{kind: "subscription", grant_config: config}),
    do: Params.parse_positive_int((config || %{})["duration_seconds"], 0)

  defp span(%Product{}), do: 0

  @doc """
  When a subscription bought now to replace one (`replaced_purchase/2`) is
  first charged: the end of the period already paid for. nil when `product`
  is not a subscription, replaces nothing, or that end is under 48 hours away
  (Stripe would refuse the wait; the plan is charged now and the old one
  refunded pro rata instead).
  """
  @spec first_charge_at(Ecto.UUID.t() | nil, Product.t(), DateTime.t()) :: DateTime.t() | nil
  def first_charge_at(user_id, product, now \\ DateTime.utc_now(:second))

  def first_charge_at(user_id, %Product{kind: "subscription"} = product, now) do
    with %Purchase{} = old <- replaced_purchase(user_id, product),
         %DateTime{} = ends_at <- period_end(old),
         seconds = DateTime.diff(ends_at, now),
         true <- seconds >= @min_deferral_seconds and seconds <= @max_deferral_seconds do
      ends_at
    else
      _charged_now -> nil
    end
  end

  def first_charge_at(_user_id, _product, _now), do: nil

  @doc """
  The checkout's `trial_end` for `product`: the later of the caller's own
  (a host's free period) and `first_charge_at/2`.
  """
  @spec trial_end(Ecto.UUID.t() | nil, Product.t(), DateTime.t() | nil) :: DateTime.t() | nil
  def trial_end(user_id, product, given) do
    case {given, first_charge_at(user_id, product)} do
      {nil, upgrade} -> upgrade
      {given, nil} -> given
      {given, upgrade} -> if DateTime.after?(upgrade, given), do: upgrade, else: given
    end
  end

  @doc """
  End the Stripe subscriptions `purchase` replaces: the buyer's other running
  Stripe subscriptions to the same entitlement, once `purchase` holds the
  row. Run after a purchase is fulfilled, and by `sweep/1`. Answers each
  ended subscription's purchase id with how it ended, or why it did not.
  """
  @spec supersede(Purchase.t()) :: {:ok, [{Ecto.UUID.t(), mode() | {:error, term()}}]}
  def supersede(%Purchase{} = purchase) do
    purchase = Repo.preload(purchase, :product)

    purchase_id = purchase.id

    with %Product{kind: kind} = product when kind in ~w(entitlement subscription) <-
           purchase.product,
         key = Payments.product_entitlement_key(product),
         %Purchase{id: ^purchase_id} <- holding_purchase(purchase.user_id, key) do
      results =
        purchase.user_id
        |> running_subscriptions(key, purchase.id)
        |> Enum.map(&{&1.id, end_subscription(&1, purchase)})

      {:ok, results}
    else
      _not_holding -> {:ok, []}
    end
  end

  @doc """
  Finish the supersessions a failure left: every running Stripe subscription
  whose entitlement row another purchase now holds. Up to `batch` holders a
  run. Answers how many subscriptions ended each way.
  """
  @spec sweep(pos_integer()) :: %{optional(atom()) => non_neg_integer()}
  def sweep(batch \\ @batch) do
    from(p in Purchase,
      join: product in assoc(p, :product),
      join: e in Entitlement,
      on: e.user_id == p.user_id and e.source_purchase_id != p.id,
      where:
        p.provider == "stripe" and p.status == "completed" and product.kind == "subscription" and
          e.status == "active",
      select: {e.source_purchase_id, e.key, %{p | product: product}}
    )
    |> Repo.all()
    |> Enum.filter(fn {_holder_id, key, purchase} ->
      running_stripe_subscription?(purchase) and not done?(purchase) and
        Payments.product_entitlement_key(purchase.product) == key
    end)
    |> Enum.map(fn {holder_id, _key, _purchase} -> holder_id end)
    |> Enum.uniq()
    |> Enum.take(batch)
    |> Enum.flat_map(fn id ->
      case Payments.get_purchase(id) do
        %Purchase{status: "completed"} = holder ->
          {:ok, results} = supersede(holder)
          results

        _gone ->
          []
      end
    end)
    |> Enum.frequencies_by(fn
      {_id, mode} when is_atom(mode) -> mode
      {_id, {:error, _reason}} -> :failed
    end)
  end

  # The user's running Stripe subscriptions to `key`, but `except_id`, not
  # ended by an earlier supersession.
  defp running_subscriptions(user_id, key, except_id) do
    from(p in Purchase,
      where:
        p.user_id == ^user_id and p.provider == "stripe" and p.status == "completed" and
          p.id != ^except_id,
      preload: [:product]
    )
    |> Repo.all()
    |> Enum.filter(fn purchase ->
      running_stripe_subscription?(purchase) and
        Payments.product_entitlement_key(purchase.product) == key and
        not done?(purchase)
    end)
  end

  defp running_stripe_subscription?(
         %Purchase{
           provider: "stripe",
           status: "completed",
           product: %Product{kind: "subscription"}
         } = purchase
       ),
       do:
         (purchase.metadata || %{})["stripe_subscription_status"] not in ~w(canceled incomplete_expired)

  defp running_stripe_subscription?(_purchase), do: false

  defp done?(%Purchase{metadata: %{"superseded" => %{"done_at" => at}}}) when is_binary(at),
    do: true

  defp done?(_purchase), do: false

  # One subscription at a time; each attempt reads the row fresh.
  defp end_subscription(%Purchase{id: old_id}, %Purchase{} = new) do
    result =
      Lock.Local.trans({__MODULE__, :supersede, old_id}, fn ->
        old = Payments.get_purchase(old_id)

        if done?(old),
          do: {:ok, recorded_mode(old)},
          else: run(old, new)
      end)

    case result do
      {:ok, mode} ->
        mode

      {:error, reason} ->
        Logger.warning(
          "Stripe subscription not superseded purchase_id=#{old_id} by=#{new.id} " <>
            "reason=#{inspect(reason) |> String.slice(0, 500)}"
        )

        Counters.count("subscription.supersede_failed",
          reason: Payments.provider_error_code(reason)
        )

        {:error, reason}
    end
  end

  # A retry keeps the mode the first attempt chose.
  defp run(%Purchase{} = old, %Purchase{} = new) do
    mode = recorded_mode(old) || mode(new, old)

    with {:ok, subscription_id} <- StripeEvents.stripe_subscription_id(old),
         {:ok, old} <- record(old, %{"by" => new.id, "mode" => Atom.to_string(mode)}),
         {:ok, extra} <- apply_mode(mode, subscription_id, old, new),
         {:ok, _old} <- record(old, Map.put(extra, "done_at", now_iso())) do
      Logger.info(
        "Stripe subscription superseded purchase_id=#{old.id} by=#{new.id} mode=#{mode} " <>
          "refund=#{inspect(extra["refund_amount"])}"
      )

      Counters.count("subscription.superseded", mode: mode, sku: old.product.sku)
      {:ok, mode}
    end
  end

  defp recorded_mode(%Purchase{metadata: %{"superseded" => %{"mode" => "now"}}}), do: :now

  defp recorded_mode(%Purchase{metadata: %{"superseded" => %{"mode" => "at_period_end"}}}),
    do: :at_period_end

  defp recorded_mode(%Purchase{}), do: nil

  @doc """
  How `new` ends `old`: at `old`'s period end when `new` is a Stripe
  subscription whose first charge waits for it (`trial_end` at or past that
  end), else now.
  """
  @spec mode(Purchase.t(), Purchase.t()) :: mode()
  def mode(%Purchase{} = new, %Purchase{} = old) do
    with %DateTime{} = starts_at <- deferred_start(new),
         %DateTime{} = ends_at <- period_end(old),
         true <- DateTime.diff(starts_at, ends_at) >= -@cover_tolerance_seconds do
      :at_period_end
    else
      _now -> :now
    end
  end

  # When a Stripe subscription bought with a `trial_end` is first charged, or
  # nil when it was charged at once.
  defp deferred_start(%Purchase{raw_provider_payload: payload}) do
    case (payload || %{})["stripe_subscription"] do
      %{"status" => "trialing", "trial_end" => trial_end} ->
        Params.unix_seconds_to_datetime(trial_end)

      _charged ->
        nil
    end
  end

  # The end of the period the subscription has been paid (or trialled) to.
  defp period_end(%Purchase{} = purchase) do
    Params.parse_datetime((purchase.metadata || %{})["stripe_subscription_current_period_end"]) ||
      purchase.expires_at
  end

  defp apply_mode(:at_period_end, subscription_id, _old, _new) do
    case Payments.stripe_adapter().cancel_subscription_at_period_end(subscription_id) do
      {:ok, _subscription} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Cancel first, as `StripeRefunds` does: a refund that then fails leaves no
  # renewal to charge, and a retry finishes it.
  defp apply_mode(:now, subscription_id, %Purchase{} = old, %Purchase{} = new) do
    adapter = Payments.stripe_adapter()

    with {:ok, subscription} <- adapter.retrieve_subscription_with_latest_invoice(subscription_id),
         subscription = Params.normalize(subscription),
         :ok <- cancel_now(adapter, subscription, old) do
      refund_unused(adapter, subscription, old, new)
    end
  end

  defp cancel_now(_adapter, %{"status" => status}, _old)
       when status in ["canceled", "incomplete_expired"],
       do: :ok

  defp cancel_now(adapter, %{"id" => subscription_id}, %Purchase{id: id}) do
    case adapter.cancel_subscription_now(subscription_id,
           idempotency_key: "supersede-cancel-#{id}"
         ) do
      {:ok, _subscription} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp refund_unused(
         _adapter,
         _subscription,
         %Purchase{metadata: %{"superseded" => %{"refund_id" => id}}} = old,
         _new
       )
       when is_binary(id),
       do: {:ok, Map.take(old.metadata["superseded"], ["refund_id", "refund_amount"])}

  defp refund_unused(adapter, subscription, %Purchase{} = old, %Purchase{} = new) do
    invoice = subscription["latest_invoice"]
    from = new.purchased_at || DateTime.utc_now(:second)

    with {:ok, payment} <- StripeRefunds.invoice_payment(invoice),
         amount when amount > 0 <-
           unused_amount(
             invoice["amount_paid"],
             item_period(subscription, "current_period_start"),
             item_period(subscription, "current_period_end"),
             from
           ),
         {:ok, refund} <-
           adapter.create_refund(payment.id,
             amount: amount,
             idempotency_key: "supersede-refund-#{old.id}",
             metadata: %{"superseded_purchase_id" => old.id, "superseded_by" => new.id}
           ) do
      refund = Params.normalize(refund)
      {:ok, %{"refund_id" => refund["id"], "refund_amount" => refund["amount"] || amount}}
    else
      # A trial paid nothing; a period already used up leaves nothing.
      {:error, :nothing_to_refund} -> {:ok, %{"refund_amount" => 0}}
      0 -> {:ok, %{"refund_amount" => 0}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The part of `amount_paid` for the time left in the period after `from`,
  rounded down to the minor unit. 0 when nothing is left or nothing is known.
  """
  @spec unused_amount(term(), DateTime.t() | nil, DateTime.t() | nil, DateTime.t()) ::
          non_neg_integer()
  def unused_amount(
        amount_paid,
        %DateTime{} = starts_at,
        %DateTime{} = ends_at,
        %DateTime{} = from
      )
      when is_integer(amount_paid) and amount_paid > 0 do
    total = DateTime.diff(ends_at, starts_at)
    left = DateTime.diff(ends_at, from)

    cond do
      total <= 0 or left <= 0 -> 0
      left >= total -> amount_paid
      true -> div(amount_paid * left, total)
    end
  end

  def unused_amount(_amount_paid, _starts_at, _ends_at, _from), do: 0

  # A subscription's period is on its items (the latest, when they differ).
  defp item_period(%{"items" => %{"data" => items}}, field) when is_list(items) do
    items
    |> Enum.map(&Params.unix_seconds_to_datetime(&1[field]))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp item_period(_subscription, _field), do: nil

  defp active_row(user_id, key) do
    now = DateTime.utc_now(:second)

    Repo.one(
      from e in Entitlement,
        where:
          e.user_id == ^user_id and e.key == ^key and e.status == "active" and
            (is_nil(e.expires_at) or e.expires_at > ^now),
        preload: [source_purchase: :product]
    )
  end

  defp record(%Purchase{id: id}, attrs) do
    purchase = Repo.get!(Purchase, id)
    metadata = purchase.metadata || %{}

    superseded =
      (metadata["superseded"] || %{})
      |> Map.put_new("requested_at", now_iso())
      |> Map.merge(attrs)

    purchase
    |> Purchase.changeset(%{metadata: Map.put(metadata, "superseded", superseded)})
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
    |> case do
      {:ok, updated} -> {:ok, Payments.preload_purchase(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp now_iso, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
