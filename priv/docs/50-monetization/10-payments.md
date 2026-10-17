---
icon: hero-credit-card
---

# Payments

Payments use a server-side ledger. Clients may start purchases through Stripe Checkout, App Store, Play Store, or Steam, but grants happen only after server validation or a signed provider webhook.

## Core concepts

- **Products:** Internal catalog rows such as coins, subscriptions, battle passes, or DLC.
- **Provider SKUs:** Provider-specific mappings, for example Stripe price IDs or store product IDs.
- **Purchases:** Provider transactions tracked by user, product, status, environment, and raw payload.
- **Entitlements:** Durable unlocks created from fulfilled purchases and revoked on refund/dispute.
- **Consumables:** One-time rewards such as coins or item packs. Grant these in hooks so your game economy stays the source of truth.

## Stripe sandbox and live mode

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

### Create a Stripe webhook endpoint

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

6. Save the endpoint.
7. Open endpoint details and copy the signing secret starting with `whsec_...`.
8. Set `GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET` or `GAMEND_PAYMENTS_STRIPE_PRODUCTION_WEBHOOK_SECRET` to that value, matching `GAMEND_PAYMENTS_ENVIRONMENT`.

Do not enable all Stripe events. Extra events add webhook traffic, stored provider events, retries, and logs without changing purchase fulfillment.

refund.failed is not enabled by default because a failed refund does not mean access should be automatically regranted; add that only with an explicit ops policy.

Do not choose Latest API version without testing. If you change GAMEND_PAYMENTS_STRIPE_API_VERSION, update the webhook endpoint to the same version and run Stripe checkout/webhook tests before production.

```text
# Local testing with Stripe CLI
stripe listen --forward-to localhost:4000/api/v1/payments/webhooks/stripe

# Use printed whsec_... as GAMEND_PAYMENTS_STRIPE_SANDBOX_WEBHOOK_SECRET
```

Detected Stripe mode and masked provider variables are visible in [Admin > Config](/admin/config).

Stripe docs: [API keys](https://docs.stripe.com/keys),
[authentication](https://docs.stripe.com/api/authentication),
[webhooks](https://docs.stripe.com/webhooks).

## Stripe Checkout setup

1. Create products and prices in Stripe Dashboard.
2. Create matching internal products in Admin > Payments.
3. Create provider SKUs with provider `stripe` and external ID `price_...`. Use the Stripe Price ID, not the Stripe Product ID.
4. Client calls `POST /api/v1/payments/checkout/stripe` with `product_sku` or `provider_product_id`.
5. Stripe sends signed events to `POST /api/v1/payments/webhooks/stripe`.
6. Server completes, refunds, or revokes purchase from webhook state.

Entitlement and subscription products are buy-once while active: checkout quantity must be 1, and users with an active grant or in-progress checkout cannot start another checkout for that product. Consumables can be bought repeatedly.

The one exception is an upgrade (`Gamend.Payments.Upgrades`). A user who holds the entitlement by a running Stripe subscription can buy a longer product with the same entitlement key: a one-off entitlement (lifetime), or a subscription whose `grant_config.duration_seconds` is longer (monthly to yearly). Once the new purchase is fulfilled it holds the entitlement, and the old subscription ends:

- A subscription bought this way is first charged when the old one's paid period ends (the checkout's `trial_end`, at least 48 hours away). The old one is set to cancel at that period end, and nothing is refunded.
- Anything else (lifetime, or a period ending within 48 hours) cancels the old subscription now and refunds the unused part of its last payment, pro rata by time.

A Stripe error there is logged and retried by the hourly sweeper. A shorter or equal plan, a grant with no purchase, and another provider's subscription still answer `already_owned`.

A Stripe checkout the player left open (Back from the payment page, a closed tab, a switch from the yearly plan to lifetime) does not hold the next one: a new Stripe checkout for the same entitlement expires the open session at Stripe, cancels its purchase and goes ahead. A session paid meanwhile is never cancelled; it is fulfilled and the new checkout answers `already_owned`, and one whose payment is still clearing answers `purchase_already_in_progress`. An open purchase from another provider (Steam) still refuses. Every Checkout Session expires 31 minutes after it is created, not Stripe's default 24 hours.

Checkout answers `{"data": {"purchase": ..., "checkout_url": ..., "provider_session_id": ...}}`. A refusal is a code: `quantity_not_allowed` (400); `already_owned` or `purchase_already_in_progress` (409); a `*_not_found` product (404); `stripe_not_configured` and every other `*_not_configured` (503), because the server is missing something, not the request. The catalog (`GET /api/v1/payments/catalog`) and the player's entitlements (`GET /api/v1/payments/entitlements`) are pages.

Apple, Google, Steam, and Stripe products that unlock the same thing must point to the same internal product, or their internal products must share the same grant_config.entitlement_key. Ownership checks use that entitlement key across providers.

Currency display is handled by Stripe Checkout. Enable Stripe Adaptive Pricing in Stripe Dashboard, or configure multi-currency Prices with currency options. The provider SKU still stores the Stripe Price ID.

```json
{
  "product_sku": "coins_100",
  "success_url": "https://your-game.example/payments/success",
  "cancel_url": "https://your-game.example/payments/cancel"
}
```

## User store and downloads

Authenticated users can open /store to test browser purchases. Stripe rows start Checkout; Apple, Google, and Steam rows remain platform-SDK/API flows.

- `/users/settings?tab=payments` shows order history, active entitlements, Stripe subscription cancellation, refunds within the refund window, and downloads.
- Consumables such as coin packs stay visible in purchase history. Use after_purchase_fulfilled/1 to grant coins or items in your game hooks.

```json
{
  "entitlement_key": "premium",
  "duration_seconds": 2592000
}
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

## Refunds, disputes and reversals

Stripe refund and dispute events are callbacks. When one takes effect it updates the purchase and revokes the entitlements created by that purchase; otherwise it is ignored.

| Event | Takes effect when | Result |
|---|---|---|
| `charge.refunded` | the charge is refunded in full (a partial refund is not a revocation) | Purchase marked refunded; entitlements revoked |
| `refund.created`, `refund.updated`, `charge.refund.updated` | the refund's status is `succeeded` (a pending, failed or cancelled refund changes nothing) | Purchase marked refunded; entitlements revoked |
| `charge.dispute.created` | always | Purchase marked revoked; entitlements revoked |
| `charge.dispute.funds_withdrawn` | always | Purchase marked revoked; entitlements revoked |

### Refunding from the site

A buyer refunds a Stripe purchase from the account page (`/users/settings?tab=payments`, Refund) within `GAMEND_PAYMENTS_REFUND_WINDOW_DAYS` of paying (14 by default; 0 turns it off). An admin refunds any Stripe purchase from Admin > Payments, with no window. The refund is always in full.

| Purchase | What happens at Stripe |
|---|---|
| Entitlement (one-off) | The payment is refunded |
| Subscription | It is cancelled now (no proration credit), then its latest invoice's payment is refunded |
| Consumable | Admin only: coins are spent the moment they land |

- **Nothing is revoked by the refund call.** The webhooks above end the purchase, as for a refund made in the Dashboard: `charge.refunded` or the refund's own events (the refund carries `metadata.purchase_id`) for a one-off payment, `customer.subscription.deleted` for a subscription. Subscribe to them.
- **The window runs from the last payment.** A one-off purchase from when it was fulfilled; a subscription from its current period start (a renewal, or the first charge after a trial), checked again against the invoice's `paid_at` before anything changes. A subscription still `trialing` has paid nothing and shows no Refund.
- **Once.** The request and the refund are recorded in the purchase's `metadata["stripe_refund"]` (`requested_at`, `by`, `refund_id`, `amount`, `refunded_at`); a recorded refund or a `refunded` purchase refuses, the refund's idempotency key is `refund-<purchase id>`, and Stripe refuses to refund a refunded payment again.
- **Cancel first.** If the refund then fails, the subscription is already over (nothing renews) and the Refund button stays, so a retry finishes it. Every refusal and failure is logged with its reason.

Recommended webhook events also include `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `customer.subscription.updated`, `customer.subscription.deleted`, and `charge.succeeded`.

## Refusing a sale

`before_purchase(user, product)` runs on every provider path before the player
is charged: return `{:error, reason}` and no money moves. Use it for the
conditions only the game knows: an account with no identity, whose entitlement
would be stranded on one device; a region you do not ship to; a banned player.

Refusing *after* the charge is not an option: the money has already moved, so
declining to fulfil takes payment and gives nothing back.

## Play Store, App Store and Steam

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

Google docs:
[purchases.products](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/get),
[purchases.subscriptionsv2](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2/get),
[real-time developer notifications](https://developer.android.com/google/play/billing/rtdn-reference).

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

Apple docs: [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi),
[Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info),
[App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications).

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

Steam docs: [ISteamMicroTxn](https://partner.steamgames.com/doc/webapi/isteammicrotxn).

## Admin and hooks

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
- **Elixir API:** [`Gamend.Payments`](https://docs.gamend.org/Gamend.Payments.html) - the functions a plugin calls, with their
  signatures and docs.
