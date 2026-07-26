---
icon: hero-bell-alert
---

# Push notifications

Deliver push notifications to your players' devices — the one channel that reaches a player whose app is backgrounded or closed. Android and Web deliver through Firebase Cloud Messaging (FCM); iOS goes straight to Apple (APNs) with no Firebase dependency. Routing is per device token, sending is server-authoritative (hooks and admin only), and delivery rides the durable job queue with retries. With no credentials configured, deliveries are logged instead of sent, so the whole flow works in development.

## Device registration

Clients obtain a token from their platform (FCM registration token or APNs device token) and register it against the authenticated user. Passing a stable device_id makes re-registration rotate the token in place instead of accumulating rows; a token re-registered by another account moves to that account. Live devices per user are capped by GAMEND_LIMITS_MAX_PUSH_TOKENS_PER_USER (default 20).

```text
POST /api/v1/me/push_tokens
token": "<platform token>", "platform": "android", "device_id": "<stable id>

# platform: "android" | "ios" | "web"
# provider defaults from the platform: ios → "apns", otherwise "fcm".
# An iOS app using Firebase instead of APNs-direct registers provider "fcm".

GET    /api/v1/me/push_tokens        # list my devices (paginated)
DELETE /api/v1/me/push_tokens/:id    # unregister (e.g. on logout)
```

### FCM setup (Android / Web)

Create a Firebase project, open Project settings → Service accounts, and generate a service-account key (JSON). Point GAMEND_PUSH_FCM_CREDENTIALS at the file (or paste the JSON inline); the project id is read from the credentials. The server obtains and refreshes the OAuth token itself.

```bash
GAMEND_PUSH_FCM_CREDENTIALS=/etc/gamend/fcm-service-account.json
```

### APNs setup (iOS, no Firebase)

In the Apple Developer portal, create an APNs auth key (Certificates, Identifiers & Profiles → Keys → enable Apple Push Notifications service) and download the .p8 file — one key serves all your apps and never expires. Configure all four variables; GAMEND_PUSH_APNS_ENV=sandbox targets Apple's sandbox gateway for development builds.

```bash
GAMEND_PUSH_APNS_PRIVATE_KEY=/etc/gamend/AuthKey_AB12CD34EF.p8
GAMEND_PUSH_APNS_KEY_ID=AB12CD34EF        # the key's 10-char id
GAMEND_PUSH_APNS_TEAM_ID=TEAM123456       # your developer team id
GAMEND_PUSH_APNS_TOPIC=com.example.game   # the app's bundle id
GAMEND_PUSH_APNS_ENV=production           # or sandbox
```

### Sending from a hook

There is no public send endpoint — pushes originate server-side. Delivery is queued per device with retries; dead tokens the provider reports are disabled automatically. Friend/chat/system notifications already bridge to push on their own: an offline recipient with a registered device gets pinged without any extra code. before_push_send/2 lets a plugin veto or rewrite any push per recipient (opt-out, quiet hours); after_push_sent/3 observes per-device outcomes — see Server-side scripting.

```elixir
GameServer.Push.send_to_user(user_id, %{
  "title" => "Your move!",
  "body" => "Ada played BRIDGE for 24 points.",
  # `data` arrives in the app
  "data" => %{"match_id" => match_id},
  # a newer push with the same key replaces the older one
  "collapse_key" => "turn-#{match_id}"
})

# Broadcasts fan out through the job queue in chunks.
GameServer.Push.send_to_users(user_ids, %{"title" => "Event starts now!"})
```

### Operations

The /admin/push page lists registered devices (filter by user, platform, provider, status) and can send a test push. Delivery jobs are visible on the push queue at /admin/oban; GAMEND_PUSH_QUEUE_CONCURRENCY sets per-node delivery throughput. Devices untouched for GAMEND_RETENTION_PUSH_TOKENS_DAYS (default 270) are pruned as dead installs. GAMEND_PUSH_ADAPTER=log forces log-only delivery even with credentials configured — useful on staging.

## Reference

- **HTTP API:** [/api/docs](/api/docs) - every endpoint, parameter and response, generated from the spec.
- **Elixir API:** [`GameServer.Push`](https://appsinacup.com/game_server/GameServer.Push.html) - the functions a plugin calls, with their
  signatures and docs.
