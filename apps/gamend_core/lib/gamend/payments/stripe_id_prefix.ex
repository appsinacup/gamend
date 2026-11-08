defmodule Gamend.Payments.StripeIdPrefix do
  @moduledoc """
  The prefixes of Stripe ids and keys.
  """

  defmacro checkout_session, do: "cs_"

  defmacro customer, do: "cus_"

  defmacro payment_intent, do: "pi_"

  defmacro charge, do: "ch_"

  defmacro payment, do: "py_"

  defmacro secret_live, do: "sk_live_"

  defmacro restricted_live, do: "rk_live_"

  defmacro secret_test, do: "sk_test_"

  defmacro restricted_test, do: "rk_test_"
end
