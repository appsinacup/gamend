defmodule Gamend.Payments.Counters do
  @moduledoc """
  What happened to payments, per day, as `Gamend.Analytics.count/3` counters:
  the admin analytics page lists them under "Counters" with the game's own.

  Every key starts with `payments.`. A dimension goes after a colon, one
  counter each, so a family reads back by prefix
  (`Analytics.counts("payments.purchase.fulfilled.sku:*")`):

    * `payments.checkout.opened` / `.refused` / `.failed` — a checkout session
      opened, refused before money could move (`reason:`), or refused by the
      provider (`reason:`). `provider:`, `sku:`.
    * `payments.purchase.fulfilled` / `.revoked` / `.restored` — the goods
      handed over, taken back (`reason:` the status it ended in), or handed
      back when a dispute was won. `provider:`, `sku:`.
    * `payments.subscription.renewed` / `.past_due` / `.cancel_scheduled` /
      `.resumed` — read off each subscription write. `sku:`.
    * `payments.subscription.superseded` / `.supersede_failed` — a plan
      that renews, ended for a longer one (`Gamend.Payments.Upgrades`), by
      `mode:` (now, at_period_end) and `sku:`, or the `reason:` it was not.
    * `payments.refund.requested` / `.failed` — a refund through
      `Gamend.Payments.StripeRefunds` (`by:` buyer or admin).
    * `payments.portal.opened` — the Stripe customer portal.
    * `payments.webhook` — every delivery, by `provider:`, `type:` and
      `result:` (processed, ignored, duplicate, failed, refused).
    * `payments.sweep` — `Gamend.Payments.StripeSweeper`, by `result:`.

  Counted after the write it describes, outside any transaction. Never
  raises and never fails the caller: a counter is not worth a payment.
  """

  alias Gamend.Analytics

  @doc "Adds one to `payments.<event>` and to each `payments.<event>.<dim>:<value>`."
  @spec count(String.t(), keyword()) :: :ok
  def count(event, dims \\ []) when is_binary(event) do
    key = "payments." <> event
    Analytics.count(key)

    Enum.each(dims, fn
      {_name, nil} -> :ok
      {_name, ""} -> :ok
      {name, value} -> Analytics.count("#{key}.#{name}:#{dim_value(value)}")
    end)

    :ok
  rescue
    # `Analytics.count/3` already swallows a failed write; this guards a value
    # `to_string/1` cannot render.
    _error -> :ok
  end

  # An error reason is often a tuple (`{:stripe_error, %{...}}`): its tag is
  # the dimension, never the payload, which would mint a key per message.
  defp dim_value(value) when is_atom(value), do: Atom.to_string(value)
  defp dim_value(value) when is_binary(value), do: String.slice(value, 0, 60)
  defp dim_value(value) when is_integer(value), do: Integer.to_string(value)

  defp dim_value(value) when is_tuple(value) and tuple_size(value) > 0,
    do: dim_value(elem(value, 0))

  defp dim_value(%Ecto.Changeset{}), do: "invalid"
  defp dim_value(_value), do: "other"
end
