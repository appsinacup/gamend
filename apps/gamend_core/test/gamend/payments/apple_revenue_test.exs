defmodule Gamend.Payments.AppleRevenueTest do
  @moduledoc """
  An App Store renewal is revenue of its own (`Gamend.Payments.Charges`), at
  the price Apple says the buyer paid; the notification repeated, or the
  first purchase's own, adds nothing.
  """
  use Gamend.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Charge
  alias Gamend.Payments.Settings

  defmodule Verifier do
    def verify_and_decode(signed) do
      case :persistent_term.get({__MODULE__, signed}, nil) do
        nil -> {:error, :invalid_apple_jws}
        payload -> {:ok, payload}
      end
    end
  end

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  setup do
    settings = Application.get_env(:gamend_core, Settings)
    verifier = Application.get_env(:gamend_core, :apple_jws_verifier)
    hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(
      :gamend_core,
      Settings,
      Keyword.merge(settings || [], apple_bundle_id: "com.example.game")
    )

    Application.put_env(:gamend_core, :apple_jws_verifier, Verifier)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore(Settings, settings)
      restore(:apple_jws_verifier, verifier)
      restore(:hooks_module, hooks)
    end)

    %{user: AccountsFixtures.user_fixture()}
  end

  test "each renewal is counted once, at its price", %{user: user} do
    {:ok, product} =
      Payments.create_product(%{
        "sku" => "pro_apple_#{System.unique_integer([:positive])}",
        "title" => "Pro",
        "kind" => "subscription",
        "grant_config" => %{"entitlement_key" => "pro_apple"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "apple",
        "external_id" => "com.example.game.pro",
        "currency" => "USD",
        "unit_amount" => 499
      })

    {:ok, purchase} =
      Payments.create_purchase(user, Repo.preload(provider_product, :product), %{
        "provider_transaction_id" => "tx_first",
        "provider_original_transaction_id" => "tx_first"
      })

    {:ok, purchase} = Payments.fulfill_purchase(purchase)
    assert [%Charge{kind: "sale", amount: 499, currency: "USD"}] = charges(purchase)

    # The first purchase's own notification, then a renewal delivered twice.
    notify("SUBSCRIBED", "tx_first", nil)
    notify("DID_RENEW", "tx_renew_1", 4990)
    notify("DID_RENEW", "tx_renew_1", 4990)

    assert [%Charge{kind: "renewal", amount: 499, currency: "USD", provider_ref: "tx_renew_1"}] =
             Enum.filter(charges(purchase), &(&1.kind == "renewal"))

    assert purchase |> charges() |> Enum.map(& &1.amount) |> Enum.sum() == 998
  end

  defp notify(type, transaction_id, price) do
    transaction =
      %{
        "productId" => "com.example.game.pro",
        "transactionId" => transaction_id,
        "originalTransactionId" => "tx_first",
        "bundleId" => "com.example.game",
        "environment" => "Sandbox",
        "purchaseDate" => DateTime.to_unix(DateTime.utc_now(), :millisecond)
      }
      |> then(&if(price, do: Map.merge(&1, %{"price" => price, "currency" => "USD"}), else: &1))

    note = "note_#{System.unique_integer([:positive])}"
    tx = "tx_#{System.unique_integer([:positive])}"
    :persistent_term.put({Verifier, tx}, transaction)

    :persistent_term.put({Verifier, note}, %{
      "notificationType" => type,
      "notificationUUID" => Ecto.UUID.generate(),
      "data" => %{"bundleId" => "com.example.game", "signedTransactionInfo" => tx}
    })

    assert {:ok, _result} =
             Payments.handle_apple_webhook(Jason.encode!(%{"signedPayload" => note}))
  end

  defp charges(purchase),
    do: Repo.all(from(c in Charge, where: c.purchase_id == ^purchase.id, order_by: c.occurred_at))

  defp restore(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore(key, value), do: Application.put_env(:gamend_core, key, value)
end
