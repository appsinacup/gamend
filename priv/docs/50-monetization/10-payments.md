---
icon: hero-credit-card
---

# Payments

Payments use a server-side ledger. Clients may start purchases through Stripe Checkout, App Store, Play Store, or Steam, but grants happen only after server validation or a signed provider webhook.

## Core Concepts

- **Products:** Internal catalog rows such as coins, subscriptions, battle passes, or DLC.
- **Provider SKUs:** Provider-specific mappings, for example Stripe price IDs or store product IDs.
- **Purchases:** Provider transactions tracked by user, product, status, environment, and raw payload.
- **Entitlements:** Durable unlocks created from fulfilled purchases and revoked on refund/dispute.
- **Consumables:** One-time rewards such as coins or item packs. Grant these in hooks so your game economy stays the source of truth.

## Stripe Sandbox And Live Mode

GAMEND_PAYMENTS_ENVIRONMENT is the global payment mode. Use sandbox for non-real provider flows, and production only when ready to charge real payment methods.

```bash
# Stripe sandbox mode (Stripe test keys)
GAMEND_PAYMENTS_ENVIRONMENT=sandbox
GAMEND_PAYMENTS_STRIPE_API_VERSION=2022-11-15
GAMEND_PAYMENTS_STRIPE_SANDBOX_SECRET_KEY=sk_test_...
GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET=whsec_...
# Stripe live mode
GAMEND_PAYMENTS_ENVIRONMENT=production
GAMEND_PAYMENTS_STRIPE_API_VERSION=2022-11-15
GAMEND_PAYMENTS_STRIPE_PRODUCTION_SECRET_KEY=sk_live_...
GAMEND_PAYMENTS_STRIPE_PRODUCTION_WEBHOOK_SECRET=whsec_...
```

- Copy the Stripe API secret key from `Developers / Workbench > API keys`. Use a `sk_test_...` key for sandbox and a `sk_live_...` key for production.
- The webhook secret is not the API key. Copy the webhook signing secret from the Stripe webhook endpoint details after the endpoint exists.
- `GAMEND_PAYMENTS_STRIPE_API_VERSION` is optional. If omitted, the Stripe SDK default is 2022-11-15; the webhook endpoint should use the same version.
- Live secret keys may be shown only once when created. Store them in deployment secrets or environment variables, never in source control.

### Create Stripe Webhook Endpoint

1. Open Stripe Dashboard `Developers / Workbench > Webhooks`.
2. Click Add endpoint.
3. Set endpoint URL to `https://your-domain.com/api/v1/payments/webhooks/stripe`.
4. For API version, choose `2022-11-15` for the default integration, or the exact value configured in GAMEND_PAYMENTS_STRIPE_API_VERSION. Checkout requests use stripity_stripe with the same API version.
5. Select only the events this server handles:

```text
checkout.session.completed
checkout.session.async_payment_succeeded
checkout.session.async_payment_failed
checkout.session.expired
customer.subscription.updated
customer.subscription.deleted
charge.succeeded
charge.refunded
refund.created
refund.updated
charge.refund.updated
charge.dispute.created
charge.dispute.funds_withdrawn
```

1. Save the endpoint.
2. Open endpoint details and copy the signing secret starting with `whsec_...`.
3. Set `GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET` or `GAMEND_PAYMENTS_STRIPE_PRODUCTION_WEBHOOK_SECRET` to that value, matching `GAMEND_PAYMENTS_ENVIRONMENT`.

Do not enable all Stripe events. Extra events add webhook traffic, stored provider events, retries, and logs without changing purchase fulfillment.

refund.failed is not enabled by default because a failed refund does not mean access should be automatically regranted; add that only with an explicit ops policy.

Do not choose Latest API version without testing. If you change GAMEND_PAYMENTS_STRIPE_API_VERSION, update the webhook endpoint to the same version and run Stripe checkout/webhook tests before production.

```text
# Local testing with Stripe CLI
stripe listen --forward-to localhost:4000/api/v1/payments/webhooks/stripe

# Use printed whsec_... as GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET
```

Detected Stripe mode and masked provider variables are visible in [Admin > Config](/admin/config).

Stripe API Keys

Stripe Authentication

Stripe Webhooks

## Stripe Checkout Setup

1. Create products and prices in Stripe Dashboard.
2. Create matching internal products in Admin > Payments.
3. Create provider SKUs with provider `stripe` and external ID `price_...`. Use the Stripe Price ID, not the Stripe Product ID.
4. Client calls `POST /api/v1/payments/checkout/stripe` with `product_sku` or `provider_product_id`.
5. Stripe sends signed events to `POST /api/v1/payments/webhooks/stripe`.
6. Server completes, refunds, or revokes purchase from webhook state.

Entitlement and subscription products are buy-once while active: checkout quantity must be 1, and users with an active grant or in-progress checkout cannot start another checkout for that product. Consumables can be bought repeatedly.

Apple, Google, Steam, and Stripe products that unlock the same thing must point to the same internal product, or their internal products must share the same grant_config.entitlement_key. Ownership checks use that entitlement key across providers.

Currency display is handled by Stripe Checkout. Enable Stripe Adaptive Pricing in Stripe Dashboard, or configure multi-currency Prices with currency options. The provider SKU still stores the Stripe Price ID.

```text
product_sku": "coins_100", "success_url": "https://your-game.example/payments/success", "cancel_url": "https://your-game.example/payments/cancel
```

## User Store And Downloads

Authenticated users can open /store to test browser purchases. Stripe rows start Checkout; Apple, Google, and Steam rows remain platform-SDK/API flows.

- `/users/settings?tab=payments` shows order history, active entitlements, Stripe subscription cancellation, and downloads.
- Consumables such as coin packs stay visible in purchase history. Use after_purchase_fulfilled/1 to grant coins or items in your game hooks.

```text
entitlement_key": "premium", "duration_seconds": 2592000 }
```

Stripe subscription entitlements stay active while the subscription auto-renews. The account page shows Renews with Stripe current_period_end when known, Auto-renews when no provider period end is stored yet, and Cancels after cancel_at_period_end is scheduled.

Cancel renewal calls Stripe and schedules cancellation at period end; it does not revoke access immediately. If a subscription shows no expiry, configure Stripe subscription webhook events and use Admin > Payments > Reconcile Stripe to backfill period data. duration_seconds is only a fallback for custom/non-Stripe flows.

```json
{
  "entitlement_key": "starter_pack",
  "download": {
    "asset_key": "starter_pack.zip",
    "filename": "starter_pack.zip"
  }
}
```

Download assets are served from the payment downloads directory or priv/downloads. Asset keys must be file names, and only active entitlement owners can download.

## Refunds, Disputes, And Reversals

Stripe refund and dispute events are callbacks. They update the purchase and revoke entitlements created by that purchase.

| Event | Result |
|---|---|
| `charge.refunded` | Purchase marked refunded; entitlements revoked |
| `refund.created` | Purchase marked refunded; entitlements revoked |
| `refund.updated` | Purchase marked refunded; entitlements revoked |
| `charge.dispute.created` | Purchase marked revoked; entitlements revoked |
| `charge.dispute.funds_withdrawn` | Purchase marked revoked; entitlements revoked |

Recommended webhook events also include `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `customer.subscription.updated`, `customer.subscription.deleted`, and `charge.succeeded`.

## Play Store, App Store, And Steam

Google, Apple, and Steam adapters are built in. They store normalized validation results in the same purchases, entitlements, and provider event tables.

### Google Play

```bash
GAMEND_PAYMENTS_ENVIRONMENT=sandbox
GAMEND_PAYMENTS_GOOGLE_PLAY_PACKAGE_NAME=com.example.game
GAMEND_PAYMENTS_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH=/run/secrets/google-play-service-account.json
GAMEND_PAYMENTS_GOOGLE_PLAY_RTDN_TOKEN=shared_push_token
GAMEND_PAYMENTS_GOOGLE_PLAY_AUTO_ACKNOWLEDGE=true
```

1. Create provider SKUs with provider `google` and external ID equal to the Play product ID.
2. Client validates one-time purchases with `POST /api/v1/payments/validate/google` using `product_id` and `purchase_token`.
3. For subscriptions, include `purchase_type: "subscription"` and `purchase_token`.
4. Configure Pub/Sub push for RTDN to `POST /api/v1/payments/webhooks/google`.

Google Product API

Google Subscriptions API

Google RTDN

### App Store

```bash
GAMEND_PAYMENTS_ENVIRONMENT=sandbox
GAMEND_PAYMENTS_APPLE_BUNDLE_ID=com.example.game
GAMEND_PAYMENTS_APPLE_ISSUER_ID=app_store_server_api_issuer_id
GAMEND_PAYMENTS_APPLE_KEY_ID=app_store_server_api_key_id
GAMEND_PAYMENTS_APPLE_PRIVATE_KEY_PATH=/run/secrets/AuthKey_ABC123DEFG.p8
```

1. Create provider SKUs with provider `apple` and external ID equal to the App Store product ID.
2. Client validates StoreKit 2 purchases with `POST /api/v1/payments/validate/apple` using `signed_transaction_info`.
3. If only transaction ID is available, send `transaction_id` and server fetches App Store Server API transaction info.
4. Configure App Store Server Notifications v2 to `POST /api/v1/payments/webhooks/apple`.

App Store Server API

Get Transaction Info

Apple Notifications

### Steam MicroTxn

```bash
GAMEND_PAYMENTS_ENVIRONMENT=sandbox
GAMEND_PAYMENTS_STEAM_WEB_API_KEY=steam_web_api_key
GAMEND_PAYMENTS_STEAM_APP_ID=480
```

If `GAMEND_PAYMENTS_STEAM_WEB_API_KEY` is unset, payments reuse `GAMEND_OAUTH_STEAM_API_KEY` from Steam OpenID config.

1. Create provider SKUs with provider `steam` and external ID equal to the numeric Steam item ID.
2. Client starts payment with `POST /api/v1/payments/checkout/steam` using `steam_id`.
3. After Steam approval, client calls `POST /api/v1/payments/steam/finalize` with `order_id`.
4. Use Steam reports for later reconciliation of refunds and chargebacks.

Steam MicroTxn API

## Admin And Hooks

Use Admin > Payments to view provider status, products, provider SKUs, purchases, entitlements, webhook events, and reconciliation cursors. Use Admin > Config to view masked provider environment variables.

Stripe purchases with a Checkout Session ID show a Reconcile Stripe action while pending, stuck, or completed. It retrieves the session from Stripe and fulfills paid sessions, cancels expired sessions, leaves open/processing sessions pending, or backfills subscription period metadata on completed subscriptions.

```text
after_purchase_fulfilled(purchase)
after_purchase_revoked(purchase)
after_entitlement_changed(entitlement)
```

Default payment hooks mirror payment state into user metadata under payments. Purchase IDs are tracked in payments.purchase_ids, entitlement keys in payments.entitlements, and entitlement IDs in payments.entitlement_ids. Subscription products use the same entitlement metadata and include expires_at in payments.entitlement_details.

Use these hooks for analytics, custom fulfillment, notifications, or external sync.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Payments`](https://appsinacup.com/game_server/GameServer.Payments.html) - the functions a plugin calls, with their
  signatures and docs.
