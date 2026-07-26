# Push — Godot client (Android → iOS)

Design spec for the Phase 1 **Push — Godot client** item in
[ROADMAP.md](../../ROADMAP.md). This is the **client half** of push; the server
half is [push.md](push.md) (the contract this targets). Ships Android first,
then iOS — hence "Android → iOS".

Goal: from a Godot game, obtain the device's push token, register it with the
server (`POST /me/push_tokens`), and surface incoming notifications to game code
as signals — with the platform plumbing (FCM on Android, native APNs on iOS)
hidden behind one GDScript API.

## Why (Godot has no push primitive)

Godot ships no push-notification support on mobile. Getting a token and
receiving a message requires native code on each platform — a Godot **Android
plugin** (Kotlin/Java, pulling in `firebase-messaging`) and a Godot **iOS
plugin** (Obj-C/Swift, using `UserNotifications`). The existing `gamend` addon
already wraps every REST domain and the realtime socket, so push slots in as one
more capability the addon exposes — the game author calls one method and
connects one signal, and never touches Firebase or `UNUserNotificationCenter`.

## Where it lives (existing addon layout)

```
godot_addons/addons/gamend/
  apis/            # generated from OpenAPI — PushApi.gd lands here after the server ships
  core/            # generated HTTP client plumbing
  GamendApi.gd     # facade
  GamendRealtime.gd# WebSocket/Phoenix channel
  GamendPush.gd    # NEW — hand-written platform-integration layer (this spec)
```

- **`PushApi.gd`** is **generated** by `mix gen.sdk` from the server's
  `/me/push_tokens` OpenAPI schemas (no hand-editing — same pipeline as
  `NotificationsApi.gd`, `PaymentsApi.gd`).
- **`GamendPush.gd`** is **hand-written** (the generator can't model native
  plugins). It orchestrates: ask the platform plugin for a token → call
  `PushApi.register_token` with the right `platform`/`provider` → re-register on
  token refresh → emit signals when a push arrives or is tapped.

## Native plugins

### Android (ships first) — FCM

A Godot **Android plugin** (`GamendPushAndroid`, Kotlin, packaged as an AAR
under the addon's `android/` export) that:

- Bundles `com.google.firebase:firebase-messaging` and a
  `FirebaseMessagingService` subclass.
- Exposes to GDScript: `request_token() -> void` (async; emits `token_received(token)`),
  and forwards `onMessageReceived` / notification taps to the engine via
  Godot's `emit_signal` plugin bridge.
- Requires the app's `google-services.json` and the Firebase Gradle plugin in
  the export preset — documented in the setup page.
- Registers tokens as `platform: "android", provider: "fcm"`.

### iOS (ships second) — native APNs

A Godot **iOS plugin** (`GamendPushIOS`, Obj-C/Swift, packaged under the addon's
`ios/` export) that:

- Calls `UNUserNotificationCenter.requestAuthorization` then
  `registerForRemoteNotifications`; captures the APNs device token in
  `didRegisterForRemoteNotificationsWithDeviceToken` (hex-encoded).
- Forwards foreground/tap notifications to the engine.
- Needs the **Push Notifications** capability + `aps-environment` entitlement in
  the export — documented in setup.
- Registers tokens as `platform: "ios", provider: "apns"` — **no Firebase SDK on
  iOS**, matching the server's APNs-direct provider (see [push.md](push.md)).
  (An alternate FCM-on-iOS path is possible but not shipped; APNs-direct keeps
  the iOS client lean.)

## GDScript API — `GamendPush.gd`

```gdscript
# One-time setup after login
Gamend.push.register()            # requests OS permission, gets token, registers with server
Gamend.push.unregister()          # deletes this device's token server-side

signal token_registered(token: String)
signal permission_denied()
signal notification_received(data: Dictionary)   # arrived while app foregrounded
signal notification_opened(data: Dictionary)     # user tapped it (cold or warm start)
```

- `register()` is idempotent: it caches the last-registered token and only
  re-hits the server on change (token refresh) or re-install.
- The platform layer is selected at runtime via `OS.get_name()`; on desktop/web
  it no-ops (or, on web, wires the browser Push API later — deferred).
- `data` carries the message's `data` map from the server `Message` — the game
  routes on `data["type"]` exactly like in-app notifications.

## Ties to the server contract

1. Client obtains a token from the platform plugin.
2. `PushApi.register_token({token, platform, provider, device_id})` — server
   upserts it (see [push.md](push.md) → `Push.register_token/2`). `device_id`
   reuses the addon's existing device id so re-installs rotate in place.
3. Server delivery (FCM/APNs) reaches the device; the plugin emits
   `notification_received` / `notification_opened`.
4. On logout, `unregister()` → `DELETE /me/push_tokens/:id`.

## Setup / permissions (documented, not code)

- **Android:** `google-services.json`, Firebase Gradle plugin, `POST_NOTIFICATIONS`
  runtime permission (Android 13+). Uses the project's custom Godot export
  templates.
- **iOS:** Apple Developer push key/cert (server side), Push Notifications
  capability, background-modes `remote-notification` for silent pushes (later).

## Testing

- Android/iOS plugins can't run in CI headless, so: unit-test `GamendPush.gd`'s
  token-caching/registration logic against a mocked `PushApi` and a fake
  platform bridge; ship a **manual test scene** (`test/push_demo.tscn`) that
  registers, prints the token, and logs incoming pushes — the same "run it, don't
  only test it" bar the server holds itself to.
- Server-side, a Log-provider push proves the round trip without real FCM/APNs.

## Deferred / rejected

- **Web push (browser Push API / VAPID): defer.** Mobile is the demand; add the
  web platform branch once the JS SDK needs it. The server `web` platform enum
  already reserves the slot.
- **Rich/interactive notifications (action buttons, images, Live Activities):
  defer** — mirrors the server-side deferral in [push.md](push.md).
- **FCM-on-iOS: rejected for the client.** APNs-direct keeps the iOS build free
  of the Firebase SDK; revisit only if a unified analytics story demands FCM.

## Definition of done

- [ ] `PushApi.gd` generated from the server spec via `mix gen.sdk` (no hand
      edits); `GamendPush.gd` facade with the signals above.
- [ ] Android plugin: token fetch + message/tap forwarding; registers `fcm`.
- [ ] iOS plugin: permission + APNs token + notification forwarding; registers
      `apns`.
- [ ] `register()`/`unregister()` idempotent; token-refresh re-registers.
- [ ] Setup docs (Android Firebase, iOS push capability) on the Uploads/… docs
      site; manual test scene committed.
- [ ] Mirrored into the sibling client repos per the multi-repo layout
      (gamend_starter / gamend_polyglot) where the addon is vendored.
