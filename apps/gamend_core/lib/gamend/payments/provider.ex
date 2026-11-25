defmodule Gamend.Payments.Provider do
  @moduledoc """
  Behaviour for a store adapter — Apple, Google, Steam, or a host's own.

  A host swaps one out through config:

      config :gamend_core, :payment_provider_adapters, apple: MyGame.AppleStub

  That seam existed before this behaviour did, which meant the contract was
  whatever `Gamend.Payments` happened to call, discoverable only by reading it.
  The symptom was `function_exported?(module, :config_status, 0)` guarding
  every call to an optional callback: a runtime probe standing in for a
  declaration.

  ## Required

  `validate_purchase/2` is the one every adapter implements: given the
  attributes a client submitted, confirm with the store that the purchase is
  real, and answer with the normalised fields (`"environment"`,
  `"provider_transaction_id"`, and whatever else the provider knows).

  ## Optional

  The rest are per-provider. Steam has a two-step init/finalize flow that the
  others do not; Apple verifies signed notifications where Google verifies a
  bearer token on the webhook. Declare only what your store actually does —
  `Gamend.Payments` checks against this list before calling.
  """

  @type attrs :: map()
  @type result :: {:ok, map()} | {:error, term()}

  @doc """
  Verifies a purchase with the store and returns its normalised fields.
  """
  @callback validate_purchase(user :: struct() | nil, attrs()) :: result()

  @doc """
  Whether this adapter has the credentials it needs, for the admin console.

  Assumed configured when not implemented.
  """
  @callback config_status() :: %{required(:configured) => boolean(), optional(atom()) => term()}

  @doc "Starts a provider-hosted checkout (Steam's init/finalize flow)."
  @callback init_transaction(purchase :: struct(), provider_product :: struct(), attrs()) ::
              result()

  @doc "Completes a checkout started by `init_transaction/3`."
  @callback finalize_transaction(purchase :: struct(), attrs()) :: result()

  @doc "Reads back one transaction's current state from the store."
  @callback query_transaction(attrs()) :: result()

  @doc "Verifies a signed store notification (Apple's App Store Server V2)."
  @callback verify_notification(raw_body :: binary()) :: result()

  @doc "Verifies a webhook's authenticity from its authorization header."
  @callback verify_webhook(raw_body :: binary(), authorization :: String.t() | nil) :: result()

  @optional_callbacks config_status: 0,
                      init_transaction: 3,
                      finalize_transaction: 2,
                      query_transaction: 1,
                      verify_notification: 1,
                      verify_webhook: 2
end
