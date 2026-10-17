defmodule Gamend.Payments.StripeSweeper do
  @moduledoc """
  The safety net for a Stripe webhook that never arrived.

  A checkout is fulfilled by `checkout.session.completed`. If that delivery
  is lost (the endpoint down for longer than Stripe's three days of retries, a
  wrong signing secret, an event left out of the endpoint's list), the buyer
  has paid and the purchase stays `requires_action` with nothing to move it.

  Hourly, this reconciles every Stripe purchase still `requires_action` past
  the checkout session's life (`Providers.Stripe` opens one for 31 minutes)
  through `Gamend.Payments.reconcile_stripe_purchase/1`: a paid one is
  fulfilled, an expired one cancelled, one whose payment is still clearing
  left for the next hour. A batch at a time, oldest first. Each result is
  counted (`payments.sweep`), and a run that changed something is logged.

  It also ends a subscription a longer plan replaced when a Stripe error left
  it running (`Gamend.Payments.Upgrades.sweep/1`).

  Idle while no Stripe secret key is configured. `enabled: false` in the app
  config keeps it supervised but idle, for test suites (`sweep/1` still
  works). Safe on several nodes at once: a reconcile locks the purchase row.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Gamend.Payments
  alias Gamend.Payments.Counters
  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.Upgrades
  alias Gamend.Repo

  @interval :timer.hours(1)
  @first :timer.minutes(7)
  # A session lives 31 minutes; past that it has been paid or has expired.
  @stale_after_seconds 35 * 60
  @batch 50

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Keyword.get(Application.get_env(:gamend_core, __MODULE__, []), :enabled, true),
      do: Process.send_after(self(), :sweep, @first)

    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    _ = sweep()
    Process.send_after(self(), :sweep, @interval)
    {:noreply, state}
  end

  @doc """
  Reconcile the Stripe checkouts left open past their session's life, as of
  `now`. Returns how many ended each way (`%{fulfilled: 1, cancelled: 3}`).
  """
  @spec sweep(DateTime.t()) :: %{atom() => non_neg_integer()}
  def sweep(now \\ DateTime.utc_now(:second)) do
    if configured?() do
      results =
        now
        |> stale_purchases()
        |> Enum.map(&reconcile/1)
        |> Enum.frequencies()
        |> Map.merge(supersede())

      if Enum.any?(results, fn {result, _count} -> result not in [:still_open] end),
        do: Logger.info("Stripe sweep reconciled open checkouts: #{inspect(results)}")

      results
    else
      %{}
    end
  rescue
    # One bad row or a database blip must not take the timer down with it;
    # the next hour tries again.
    exception ->
      Logger.error("Stripe sweep failed\n" <> Exception.format(:error, exception, __STACKTRACE__))
      %{}
  end

  # A plan given up for a longer one that a Stripe error left running
  # (`Upgrades.sweep/1`), counted apart from the checkouts.
  defp supersede do
    Map.new(Upgrades.sweep(), fn
      {:now, count} -> {:superseded_now, count}
      {:at_period_end, count} -> {:superseded_at_period_end, count}
      {:failed, count} -> {:supersede_failed, count}
    end)
  end

  defp configured? do
    case ProviderConfig.stripe_secret_key() do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  defp stale_purchases(now) do
    cutoff = DateTime.add(now, -@stale_after_seconds, :second)

    from(p in Purchase,
      where:
        p.provider == "stripe" and p.status == "requires_action" and
          like(p.provider_transaction_id, "cs_%") and p.updated_at < ^cutoff,
      order_by: [asc: p.inserted_at],
      limit: @batch
    )
    |> Repo.all()
  end

  defp reconcile(%Purchase{} = purchase) do
    result =
      case Payments.reconcile_stripe_purchase(purchase) do
        {:ok, %{result: result}} ->
          result

        {:error, reason} ->
          Logger.warning(
            "Stripe sweep could not reconcile purchase_id=#{purchase.id} order_id=#{purchase.order_id} " <>
              "reason=#{inspect(reason) |> String.slice(0, 500)}"
          )

          :error
      end

    Counters.count("sweep", result: result)
    result
  end
end
