defmodule Gamend.Payments.DeletedAccountSubscriptions do
  @moduledoc """
  A deleted account stops being charged.

  Its entitlements go with its row and its purchases lose their owner, so
  nothing would ever tell Stripe, which goes on renewing.
  `Gamend.Accounts.delete_user/1` reads the account's subscriptions first
  (`of_user/1`), while its purchases still say whose they are, and queues a job
  for each once the row is gone (`cancel/1`), so an account whose delete failed
  keeps them.

  A job rather than a call in the delete: an admin's click or a retention sweep
  should not wait on Stripe, and an outage must not lose a cancellation nothing
  else would revisit. Every Stripe purchase the account made with a
  subscription gets one, and the job asks Stripe what is still live, so a
  renewal that is past due counts and one already over is left alone. Cancelled
  now, with no refund (`Gamend.Payments.Providers.Stripe.cancel_subscription_now/2`).
  """

  use Oban.Worker, queue: :default, max_attempts: 20

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Gamend.Payments
  alias Gamend.Payments.Purchase
  alias Gamend.Payments.StripeEvents
  alias Gamend.Repo

  @stripe "stripe"
  @ended ~w(canceled incomplete_expired)
  @missing "resource_missing"

  @doc "The Stripe subscriptions `user_id`'s purchases started, whatever became of them."
  @spec of_user(Ecto.UUID.t()) :: [String.t()]
  def of_user(user_id) when is_binary(user_id) do
    from(p in Purchase, where: p.user_id == ^user_id and p.provider == @stripe)
    |> Repo.all()
    |> Enum.flat_map(fn purchase ->
      case StripeEvents.stripe_subscription_id(purchase) do
        {:ok, subscription_id} -> [subscription_id]
        {:error, _none} -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc "Queue the end of each subscription."
  @spec cancel([String.t()]) :: :ok
  def cancel(subscription_ids) when is_list(subscription_ids) do
    Enum.each(subscription_ids, fn subscription_id ->
      {:ok, _job} = Gamend.Jobs.enqueue(__MODULE__, %{"subscription_id" => subscription_id})
    end)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => subscription_id}}) do
    adapter = Payments.stripe_adapter()

    with {:ok, %{"status" => status}} when status not in @ended <-
           adapter.retrieve_subscription(subscription_id),
         {:ok, _cancelled} <- adapter.cancel_subscription_now(subscription_id, []) do
      Logger.info("Stripe subscription #{subscription_id} cancelled: its account was deleted")
      :ok
    else
      {:ok, _already_over} -> :ok
      {:error, reason} -> if missing?(reason), do: :ok, else: {:error, reason}
    end
  end

  defp missing?({:stripe_error, %{} = error}),
    do: (get_in(error, ["extra", "raw_error", "code"]) || error["code"]) == @missing

  defp missing?(_reason), do: false
end
