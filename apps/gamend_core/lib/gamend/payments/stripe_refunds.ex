defmodule Gamend.Payments.StripeRefunds do
  @moduledoc """
  Refunding a Stripe purchase in full: the buyer's own, within
  `refund_window_days` of paying (account settings, Payments), or any Stripe
  purchase from the admin page.

  A one-off payment is refunded. A subscription is cancelled now and its last
  payment refunded. Cancelling comes first: a refund that then fails leaves no
  renewal to charge, and a retry finishes it.

  Nothing is revoked here. What the refund bought ends through the webhooks
  that already handle a refund made in the Stripe Dashboard: `charge.refunded`
  (and the refund's own events, which carry the purchase id) for a one-off
  payment, `customer.subscription.deleted` for a subscription. One path,
  whoever refunds.

  The purchase's `metadata["stripe_refund"]` records the request
  (`requested_at`, `by`) before Stripe is called and the refund (`refund_id`,
  `amount`, `refunded_at`) after it. A purchase is refunded once: a recorded
  refund or a `refunded` status refuses, the refund's idempotency key is the
  purchase id, and Stripe refuses a second refund of a refunded payment.
  """

  import Ecto.Query, only: [from: 2]

  require Logger
  alias Gamend.Accounts.User
  alias Gamend.Lock
  alias Gamend.Payments
  alias Gamend.Payments.Counters
  alias Gamend.Payments.Params
  alias Gamend.Payments.Product
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.Settings
  alias Gamend.Payments.StripeEvents
  alias Gamend.Repo

  # What a buyer can refund themselves: things a revocation takes back. A
  # consumable (coins) is spent the moment it lands, so only an admin refunds
  # one.
  @self_serve_kinds ~w(entitlement subscription)

  @type result :: {:ok, %{purchase: Purchase.t(), refund: map()}} | {:error, term()}

  @doc "Days after paying in which a buyer can refund; 0 when self-serve refunds are off."
  @spec refund_window_days() :: non_neg_integer()
  def refund_window_days do
    case Gamend.Settings.get(Settings, :refund_window_days) do
      days when is_integer(days) and days > 0 -> days
      _off -> 0
    end
  end

  @doc """
  Whether the buyer can refund `purchase` themselves now: a completed Stripe
  purchase of an entitlement or a subscription, paid within the window, not
  refunded yet, and the buyer's own refunds not used up
  (`self_refunds_per_account`). A subscription still in a free trial has paid
  nothing. Reads the row, and the buyer's other purchases only when the row
  passes; the refund checks the window again against Stripe's own payment
  date.
  """
  @spec refundable?(Purchase.t(), DateTime.t()) :: boolean()
  def refundable?(%Purchase{} = purchase, now \\ DateTime.utc_now(:second)) do
    purchase |> Repo.preload(:product) |> check_buyer(now) == :ok
  end

  @doc "Whether an admin can refund `purchase`: any Stripe purchase not refunded yet, at any time."
  @spec admin_refundable?(Purchase.t()) :: boolean()
  def admin_refundable?(%Purchase{} = purchase), do: check_refundable(purchase) == :ok

  @doc """
  Refund the buyer's own purchase (`refundable?/2`). Another account's
  purchase answers `:purchase_not_found`.
  """
  @spec refund_stripe_purchase(User.t(), Ecto.UUID.t()) :: result()
  def refund_stripe_purchase(%User{id: user_id}, purchase_id) do
    run(purchase_id, "buyer", fn
      %Purchase{user_id: ^user_id} = purchase -> check_buyer(purchase, DateTime.utc_now(:second))
      %Purchase{} -> {:error, :purchase_not_found}
    end)
  end

  @doc "Refund any Stripe purchase not refunded yet, with no window: the admin page's."
  @spec admin_refund_stripe_purchase(Ecto.UUID.t()) :: result()
  def admin_refund_stripe_purchase(purchase_id) do
    run(purchase_id, "admin", &check_refundable/1)
  end

  # One refund of a purchase at a time; each step reads the row fresh.
  defp run(purchase_id, by, check) do
    result =
      Lock.Local.trans({__MODULE__, :refund, purchase_id}, fn ->
        with %Purchase{} = purchase <- Payments.get_purchase(purchase_id) || :not_found,
             :ok <- check.(purchase) do
          refund(purchase, by)
        else
          :not_found -> {:error, :purchase_not_found}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, %{refund: refund}} ->
        Logger.info(
          "Stripe refund created purchase_id=#{purchase_id} by=#{by} refund_id=#{refund["id"]}"
        )

        Counters.count("refund.requested", by: by)
        result

      {:error, reason} ->
        Logger.warning(
          "Stripe refund failed purchase_id=#{purchase_id} by=#{by} reason=#{inspect(reason)}"
        )

        Counters.count("refund.failed", by: by, reason: Payments.provider_error_code(reason))
        result
    end
  end

  defp check_refundable(%Purchase{provider: "stripe"} = purchase) do
    cond do
      refunded?(purchase) -> {:error, :already_refunded}
      purchase.status == "completed" -> :ok
      # A subscription cancelled by an earlier request whose refund then failed.
      purchase.status == "cancelled" and requested?(purchase) -> :ok
      true -> {:error, :not_refundable}
    end
  end

  defp check_refundable(%Purchase{}), do: {:error, :not_stripe_purchase}

  defp check_buyer(%Purchase{} = purchase, now) do
    with :ok <- check_refundable(purchase),
         :ok <- check_kind(purchase),
         {:ok, paid_at} <- paid_at(purchase),
         :ok <- check_window(paid_at, now) do
      check_limit(purchase)
    end
  end

  @doc "How many refunds a buyer can make themselves over the account's life; 0 for no limit."
  @spec self_refunds_per_account() :: non_neg_integer()
  def self_refunds_per_account do
    case Gamend.Settings.get(Settings, :self_refunds_per_account) do
      count when is_integer(count) and count > 0 -> count
      _no_limit -> 0
    end
  end

  # Buy, use, refund, buy again: each turn costs the seller the provider's
  # fee and gives the buyer the goods for nothing, so a buyer refunds from
  # the settings page a set number of times (`self_refunds_per_account`).
  # Only the buyer's own refunds count, and an admin is never held to it.
  # Read last, after the checks that read only the row: it is a query.
  defp check_limit(%Purchase{user_id: user_id, id: purchase_id}) do
    limit = self_refunds_per_account()

    used =
      if limit > 0 do
        from(p in Purchase,
          where: p.user_id == ^user_id and p.provider == "stripe" and p.id != ^purchase_id,
          select: p.metadata
        )
        |> Repo.all()
        |> Enum.count(&buyer_refunded?/1)
      end

    if limit > 0 and used >= limit, do: {:error, :refund_limit_reached}, else: :ok
  end

  defp buyer_refunded?(%{"stripe_refund" => %{"by" => "buyer", "refund_id" => id}})
       when is_binary(id),
       do: true

  defp buyer_refunded?(_metadata), do: false

  defp check_kind(%Purchase{product: %Product{kind: kind}}) when kind in @self_serve_kinds,
    do: :ok

  defp check_kind(%Purchase{}), do: {:error, :not_refundable}

  defp check_window(%DateTime{} = paid_at, now) do
    days = refund_window_days()

    if days > 0 and DateTime.diff(now, paid_at) <= days * 86_400,
      do: :ok,
      else: {:error, :refund_window_closed}
  end

  defp refunded?(%Purchase{status: "refunded"}), do: true
  defp refunded?(%Purchase{} = purchase), do: is_binary(stripe_refund(purchase)["refund_id"])

  defp requested?(%Purchase{} = purchase), do: is_binary(stripe_refund(purchase)["requested_at"])

  defp stripe_refund(%Purchase{metadata: %{"stripe_refund" => %{} = refund}}), do: refund
  defp stripe_refund(%Purchase{}), do: %{}

  # When the buyer last paid, as the row knows it: a one-off purchase when it
  # was fulfilled; a subscription when its current period started, if that is
  # later (a renewal, or the first charge at the end of a trial).
  defp paid_at(%Purchase{product: %Product{kind: "subscription"}} = purchase) do
    case (purchase.raw_provider_payload || %{})["stripe_subscription"] do
      %{"status" => "trialing"} ->
        {:error, :nothing_to_refund}

      subscription ->
        [purchase.purchased_at, period_start(subscription)]
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> nil end)
        |> paid_at_result()
    end
  end

  defp paid_at(%Purchase{purchased_at: purchased_at}), do: paid_at_result(purchased_at)

  defp paid_at_result(%DateTime{} = at), do: {:ok, at}
  defp paid_at_result(nil), do: {:error, :nothing_to_refund}

  # A subscription's period is on its items.
  defp period_start(%{} = subscription), do: items_period_start(subscription["items"])

  defp period_start(_subscription), do: nil

  defp items_period_start(%{"data" => items}) when is_list(items) do
    items
    |> Enum.map(&Params.unix_seconds_to_datetime(&1["current_period_start"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp items_period_start(_items), do: nil

  defp refund(%Purchase{product: %Product{kind: "subscription"}} = purchase, by) do
    with {:ok, subscription_id} <- StripeEvents.stripe_subscription_id(purchase),
         {:ok, subscription} <-
           Payments.stripe_adapter().retrieve_subscription_with_latest_invoice(subscription_id),
         subscription <- Params.normalize(subscription),
         {:ok, payment} <- invoice_payment(subscription["latest_invoice"]),
         :ok <- check_payment_window(payment, by),
         {:ok, purchase} <- record_request(purchase, by),
         :ok <- cancel_now(subscription, purchase) do
      refund_payment(purchase, payment.id)
    end
  end

  defp refund(%Purchase{} = purchase, by) do
    with {:ok, payment_id} <- one_off_payment_id(purchase),
         {:ok, purchase} <- record_request(purchase, by) do
      refund_payment(purchase, payment_id)
    end
  end

  # The buyer's window, checked again against the day Stripe took the
  # payment, which the row only knows as the period start.
  defp check_payment_window(%{paid_at: %DateTime{} = paid_at}, "buyer"),
    do: check_window(paid_at, DateTime.utc_now(:second))

  defp check_payment_window(_payment, _by), do: :ok

  defp cancel_now(%{"status" => status}, _purchase)
       when status in ["canceled", "incomplete_expired"],
       do: :ok

  defp cancel_now(%{"id" => subscription_id}, %Purchase{id: purchase_id}) do
    case Payments.stripe_adapter().cancel_subscription_now(subscription_id,
           idempotency_key: "refund-cancel-#{purchase_id}"
         ) do
      {:ok, _subscription} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp refund_payment(%Purchase{} = purchase, payment_id) do
    case Payments.stripe_adapter().create_refund(payment_id,
           idempotency_key: "refund-#{purchase.id}",
           metadata: %{"purchase_id" => purchase.id, "order_id" => purchase.order_id}
         ) do
      {:ok, refund} ->
        refund = Params.normalize(refund)

        with {:ok, purchase} <-
               record(purchase, %{
                 "refund_id" => refund["id"],
                 "amount" => refund["amount"],
                 "refunded_at" => now_iso()
               }) do
          {:ok, %{purchase: purchase, refund: refund}}
        end

      {:error, reason} ->
        if stripe_error_code(reason) == "charge_already_refunded",
          do: {:error, :already_refunded},
          else: {:error, reason}
    end
  end

  @doc false
  # The payment behind a subscription's latest invoice, when money was taken:
  # `%{id: "pi_…" | "ch_…", paid_at: DateTime | nil}`. A trial's invoice is
  # paid with nothing. Public for `Gamend.Payments.Upgrades`.
  def invoice_payment(%{"status" => "paid", "amount_paid" => amount} = invoice)
      when is_integer(amount) and amount > 0 do
    case invoice_payment_id(invoice) do
      nil ->
        {:error, :missing_stripe_payment_id}

      id ->
        paid_at =
          Params.unix_seconds_to_datetime(get_in(invoice, ["status_transitions", "paid_at"]))

        {:ok, %{id: id, paid_at: paid_at}}
    end
  end

  def invoice_payment(_invoice), do: {:error, :nothing_to_refund}

  # The paid entry of the invoice's `payments` (expanded by the adapter).
  defp invoice_payment_id(invoice) do
    case get_in(invoice, ["payments", "data"]) do
      data when is_list(data) ->
        data
        |> Enum.flat_map(fn
          %{"status" => "paid", "payment" => %{} = payment} ->
            [payment["payment_intent"], payment["charge"]]

          _other ->
            []
        end)
        |> Enum.map(&object_id/1)
        |> Enum.find(&payment_id?/1)

      _none ->
        nil
    end
  end

  defp one_off_payment_id(%Purchase{} = purchase) do
    metadata = purchase.metadata || %{}
    payload = purchase.raw_provider_payload || %{}

    [
      metadata["stripe_payment_intent_id"],
      (payload["stripe_session"] || %{})["payment_intent"],
      payload["stripe_charge"],
      purchase.provider_original_transaction_id
    ]
    |> Enum.map(&object_id/1)
    |> Enum.find(&payment_id?/1)
    |> case do
      nil -> {:error, :missing_stripe_payment_id}
      id -> {:ok, id}
    end
  end

  defp object_id(%{"id" => id}), do: id
  defp object_id(id), do: id

  defp payment_id?("pi_" <> _rest), do: true
  defp payment_id?("ch_" <> _rest), do: true
  defp payment_id?("py_" <> _rest), do: true
  defp payment_id?(_value), do: false

  defp stripe_error_code({:stripe_error, %{} = error}) do
    get_in(error, ["extra", "raw_error", "code"]) || error["code"]
  end

  defp stripe_error_code(_reason), do: nil

  # Before Stripe is called, so a webhook the call sets off reads a row that
  # already has it (the subscription handlers rewrite `metadata` from the row
  # they read).
  defp record_request(%Purchase{} = purchase, by),
    do: record(purchase, %{"requested_at" => now_iso(), "by" => by})

  defp record(%Purchase{id: id}, attrs) do
    purchase = Repo.get!(Purchase, id)
    metadata = purchase.metadata || %{}
    stripe_refund = Map.merge(metadata["stripe_refund"] || %{}, attrs)

    purchase
    |> Purchase.changeset(%{metadata: Map.put(metadata, "stripe_refund", stripe_refund)})
    |> Repo.update()
    |> Payments.tap_bump({:payments, :purchase_version})
    |> case do
      {:ok, updated} -> {:ok, Payments.preload_purchase(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp now_iso, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
