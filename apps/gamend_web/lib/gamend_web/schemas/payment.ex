defmodule GamendWeb.Schemas.PaymentProduct do
  @moduledoc "A product in the store, whichever provider sells it."
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaymentProduct",
    description: "A store product",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      sku: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      kind: %Schema{type: :string, description: "What buying it grants, e.g. `entitlement`"},
      metadata: FreeForm.metadata()
    },
    required: [:id, :sku, :title, :description, :kind, :metadata]
  })
end

defmodule GamendWeb.Schemas.PaymentCatalogEntry do
  @moduledoc "A product as one provider sells it: its id there and its price."
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias GamendWeb.Schemas.PaymentProduct
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaymentCatalogEntry",
    description: "A product on one provider",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      provider: %Schema{type: :string, description: "`stripe`, `steam`, `apple` or `google`"},
      external_id: %Schema{type: :string, description: "The product's id at the provider"},
      currency: %Schema{type: :string, description: "Empty when the provider prices it"},
      unit_amount: %Schema{
        type: :integer,
        nullable: true,
        description: "Price in the currency's minor unit; null when the provider prices it"
      },
      metadata: FreeForm.metadata(),
      product: PaymentProduct
    },
    required: [:id, :provider, :external_id, :currency, :unit_amount, :metadata, :product]
  })
end

defmodule GamendWeb.Schemas.Purchase do
  @moduledoc "A purchase, as `GamendWeb.Api.V1.PaymentController` sends it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Purchase",
    description: "A purchase",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      order_id: %Schema{type: :string},
      provider: %Schema{type: :string},
      provider_transaction_id: %Schema{
        type: :string,
        description: "Empty until the provider assigns one"
      },
      status: %Schema{type: :string},
      product_id: %Schema{type: :string, format: :uuid},
      provider_product_id: %Schema{
        type: :string,
        description: "Empty when not sold through the catalog"
      },
      quantity: %Schema{type: :integer},
      currency: %Schema{type: :string},
      amount: %Schema{
        type: :integer,
        nullable: true,
        description: "Minor units; null when unknown"
      },
      environment: %Schema{type: :string, description: "`production` or a sandbox"},
      purchased_at: %Schema{type: :string, format: :"date-time", nullable: true},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      revoked_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [
      :id,
      :order_id,
      :provider,
      :provider_transaction_id,
      :status,
      :product_id,
      :provider_product_id,
      :quantity,
      :currency,
      :amount,
      :environment,
      :purchased_at,
      :expires_at,
      :revoked_at
    ]
  })
end

defmodule GamendWeb.Schemas.Entitlement do
  @moduledoc "Something the caller owns, granted by a purchase or by the server."
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Entitlement",
    description: "An owned entitlement",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string, description: "What the game checks for"},
      status: %Schema{type: :string},
      product_id: %Schema{type: :string, description: "Empty when not granted by a product"},
      source_purchase_id: %Schema{
        type: :string,
        description: "Empty when not granted by a purchase"
      },
      starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Null for a permanent entitlement"
      },
      revoked_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: FreeForm.metadata()
    },
    required: [
      :id,
      :key,
      :status,
      :product_id,
      :source_purchase_id,
      :starts_at,
      :expires_at,
      :revoked_at,
      :metadata
    ]
  })
end

defmodule GamendWeb.Schemas.StripeCheckout do
  @moduledoc "A started Stripe Checkout: send the player to `checkout_url`."
  require OpenApiSpex
  alias GamendWeb.Schemas.Purchase
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "StripeCheckout",
    description: "A pending purchase and the Stripe page that pays it",
    type: :object,
    properties: %{
      purchase: Purchase,
      checkout_url: %Schema{type: :string},
      provider_session_id: %Schema{type: :string}
    },
    required: [:purchase, :checkout_url, :provider_session_id]
  })
end

defmodule GamendWeb.Schemas.SteamCheckout do
  @moduledoc "A started Steam MicroTxn: the overlay confirms it, then finalize."
  require OpenApiSpex
  alias GamendWeb.Schemas.Purchase
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SteamCheckout",
    description: "A pending purchase and its Steam transaction",
    type: :object,
    properties: %{
      purchase: Purchase,
      provider_transaction_id: %Schema{type: :string},
      steam_url: %Schema{type: :string, description: "Empty when Steam gave none"}
    },
    required: [:purchase, :provider_transaction_id, :steam_url]
  })
end

defmodule GamendWeb.Schemas.PurchaseValidation do
  @moduledoc "A store receipt checked with its provider."
  require OpenApiSpex
  alias GamendWeb.Schemas.Purchase
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PurchaseValidation",
    description: "The validated purchase",
    type: :object,
    properties: %{
      purchase: Purchase,
      seen_before: %Schema{
        type: :boolean,
        description: "The receipt was already validated; nothing was granted again"
      }
    },
    required: [:purchase, :seen_before]
  })
end

defmodule GamendWeb.Schemas.PaymentWebhookReceipt do
  @moduledoc "What the server did with a provider's webhook event."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PaymentWebhookReceipt",
    description: "The event's outcome",
    type: :object,
    properties: %{
      status: %Schema{
        type: :string,
        enum: ["processed", "ignored", "duplicate"],
        description: "`ignored` for an event type the server does not act on"
      }
    },
    required: [:status]
  })
end

defmodule GamendWeb.Schemas.PaymentCatalogEntryPage do
  @moduledoc "A page of the store catalog."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.PaymentCatalogEntry
end

defmodule GamendWeb.Schemas.EntitlementPage do
  @moduledoc "A page of entitlements."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Entitlement
end

defmodule GamendWeb.Schemas.PurchaseResponse do
  @moduledoc "One purchase under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Purchase
end

defmodule GamendWeb.Schemas.StripeCheckoutResponse do
  @moduledoc "A Stripe checkout under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.StripeCheckout
end

defmodule GamendWeb.Schemas.SteamCheckoutResponse do
  @moduledoc "A Steam checkout under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.SteamCheckout
end

defmodule GamendWeb.Schemas.PurchaseValidationResponse do
  @moduledoc "A validated purchase under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PurchaseValidation
end

defmodule GamendWeb.Schemas.PaymentWebhookReceiptResponse do
  @moduledoc "A webhook outcome under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PaymentWebhookReceipt
end
