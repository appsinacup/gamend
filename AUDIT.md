# Security & correctness audit — September 2026

Findings from a full read-only audit of the codebase at commit `30648abc6`.
Every item was verified against the source before being listed here.

**70 findings fixed, 4 partially fixed** — each partial is noted inline with what
remains and why. The descriptions stay in the past tense as the record of what was
wrong; line numbers refer to `30648abc6`, so they have since moved.

Verified with both test suites (3,017 web + 27 host), `mix credo --strict` on both
apps, `mix format --check-formatted`, `mix gamend.api.lint`, and a
drop/create/migrate/rollback cycle for the two new migrations.

Three fixes change behaviour on purpose:

- **Logout revokes on every device.** It is `token_version`-based, which is
  account-wide; the endpoint always claimed to invalidate the session and
  previously did nothing at all.
- **Linking an OAuth provider retires the account's device credential.** A device
  id is a bearer credential unaffected by `token_version`; re-attach deliberately
  via `link_device_id/2`.
- **Claiming another account's push token requires the matching `device_id`.**
  Account switching on one device still works; a bare token string no longer moves
  a registration.

One fix needs an operator action: the Compose files no longer carry a
`GAMEND_AUTH_SECRET_KEY_BASE`, they require one. Anyone already running from the
old file should treat that key as compromised, generate a new one, and revoke
sessions.

Status: `[ ]` open · `[x]` fixed · `[~]` partially fixed (the note says what remains)

---

## Critical

- [x] **Compose files ship a published signing key.** `docker-compose.yml:14`,
  `docker-compose.multi.yml:36` hard-code `GAMEND_AUTH_SECRET_KEY_BASE`, and
  Guardian falls back to it (`host_runtime.ex:534`). Anyone reading the repo can
  mint a JWT for any account, admin included.
- [x] **Any signed-in user can delete any passwordless account.**
  `live/user_live/settings.ex:257` reads `conflict_user_id` from the query string;
  `settings/account_tab.ex:436` deletes that user whenever `hashed_password` is nil.
- [x] **Steam checkout lets the client set the price.** `payments.ex:177` uses
  `attrs["amount"]`/`attrs["currency"]`; `payment_controller.ex:123` forwards the
  whole body. Also accepts `status`, `expires_at`, provider transaction fields.
- [x] **Plugin builder runs `mix` in any directory the request names.**
  `admin_live/config.ex:2039` never checks the name against the buildable list;
  `plugin_builder.ex:66` joins it with no basename. Admin session → code execution.

## High

- [x] **Registration accepts a device id.** `accounts.ex:958` writes any submitted
  `device_id`; device login is a plain lookup. Decision: drop device id from
  registration, and clear it when the account is later linked/confirmed by another
  method (link the provider, but that account can no longer use device auth).
- [x] **Steam ticket login uses `ownersteamid`.** `oauth/exchanger.ex:432` should
  use `steamid`; Family Sharing otherwise signs the borrower into the owner's account.
- [x] **OAuth state is not bound to the finishing browser.** `auth_controller.ex:96`,
  `:131`, `:1426`. Enables token theft via the API polling flow and account linking
  onto an attacker's account.
- [x] **Client hook calls reach scheduled job callbacks.** `plugin_manager.ex:143`
  checks only `internal_hooks`; `hooks.ex:386` also blocks `Schedule.registered_callbacks`.
- [x] **Lobby update mass assignment.** `lobby_controller.ex:884` forwards all params;
  `lobbies/lobby.ex:50` casts `host_id`, `hostless`, `password_hash`. Hostless makes
  the lobby permanently unmanageable.
- [x] **Sandbox/TestFlight purchases fulfilled in production.** `providers/apple.ex:135`,
  `providers/google.ex:162` never compare environment with the configured one.
- [x] **Webhook events marked processed before processing.** `payments.ex:383`, `:530`,
  `:544`, `:817`. A handler failure loses the event permanently; the retry is deduped.
- [x] **Fulfilment hook can fire twice.** `payments.ex:1356` resets a completed purchase
  to pending; `:240` reads without a lock. Bundled example hook grants without an
  idempotency key.
- [x] **Malformed WebRTC offer kills the channel.** `user_channel.ex:189` validates only
  the SDP key; `webrtc_peer.ex:148` asserts `:ok =`. Started with `start_link`, so the
  crash skips `terminate/2` — leaks the matchmaking ticket and leaves the user online.
- [x] **Kicked members keep the channel.** `lobby_channel.ex:145`, `group_channel.ex:115`,
  `party_channel.ex:103` never stop the affected member's channel.
- [x] **WebRTC rooms admit non-members by default.** `signaling.ex:170` falls through to
  a late-join branch; `lobbies/lobby.ex:38` defaults it to `true`.
- [x] **Tournament can finish twice.** `tournaments.ex:477` is an unconditional state
  write, reachable from the public show endpoint (`tournament_controller.ex:122`).
  Doubles prize payouts and the next recurrence.
- [x] **Matchmaking sweep holds the only DB writer while calling a plugin.**
  `matchmaking/worker.ex:119`/`:154` + `lock.ex:112` + 60s hook timeout.
- [x] **`mask_secret` reveals ~half of every secret.** `admin_live/config.ex:2836`.
- [x] **Runtime page prints secrets missed by a regex.** `runtime_introspection.ex:189`
  ignores the declared `secret: true` flag; leaks `GAMEND_DB_URL` and the Google Play
  service-account JSON.
- [x] **Ten critical sections take a lock that is a no-op on SQLite.**
  `repo/advisory_lock.ex:8` says so itself; callers should use `Gamend.Lock.serialize/3`.
- [x] **Group can be left with zero admins.** `groups.ex:962` (demote), `:837` (kick)
  have no last-admin guard and no lock. Group becomes permanently unmanageable.
  The audit's fix added the guard but not the lock, so two admins demoting or
  kicking each other at once still both landed. Since October 2026 kick, promote
  and demote re-check under `Lock.serialize(:group, …)` (`change_member/4`), and
  `Gamend.GroupAdminRaceTest` races them directly.
- [x] **Party leader handover is lockless.** `parties.ex:933`. Concurrent leaves orphan
  the party and lock the successor out of creating one (unique index on `leader_id`).

## Medium

- [x] **Metrics endpoint open when no token is set.** `plugs/metrics_auth.ex:56` allows
  every caller. Decision: deny non-loopback when no token is configured.
- [x] **Refresh tokens accepted as access tokens.** `auth/pipeline.ex:14`,
  `auth/optional_pipeline.ex:19`, `channels/user_socket.ex:61` omit the `typ` claim.
- [x] **Logout revokes nothing; deactivation does not either.** `session_controller.ex:160`
  is a no-op; `guardian.ex:41` never checks activation; email change does not bump
  `token_version`; `revoke_all_tokens/1` has no caller.
- [x] **Browser login misses the auth rate bucket.** `rate_limiter.ex:169` matches
  `log-in`, the route is `/users/log_in`.
- [x] **Hidden groups readable without a token.** `router/shared.ex:412`; member listing
  also returns `profile_url`, `is_online`, `last_seen_at`.
- [x] **KV reads default to public across users.** `hooks.ex:1587` returns `:public`;
  `kv_controller.ex:46` and `user_channel.ex:140` take the target id from the caller.
- [x] **Clients can create hostless lobbies.** `lobby_controller.ex:595` rejects only
  boolean `true`; `parties.ex:1280` does not check at all.
- [x] **Party update mass assignment.** `party_controller.ex:776` → `parties/party.ex:46`
  casts `leader_id`.
- [x] **Group `icon_url` settable via PATCH,** bypassing the upload feature gate.
  `group_controller.ex:850` → `groups/group.ex:44`.
- [x] **Google RTDN cannot authenticate and is trusted anyway.** `providers/google.ex:304`
  expects a static bearer header Pub/Sub cannot send; handlers fulfil from the message body.
- [x] **Subscription receipts replayable by a second account.** `payments.ex:330` dedupes
  only on the per-transaction id, never the original.
- [x] **Password-protected lobbies are spectatable.** `lobbies.ex:1596` ignores
  `password_hash`; spectators get chat and the member list.
- [x] **`kv:subscribe` unbounded per socket.** `user_channel.ex:663` — no cap, no key
  length limit.
- [x] **Matchmaking double-queue.** `matchmaking.ex:128` is a bare existence check with
  the join hook between it and the insert; no unique index on queued tickets.
- [x] **Tournament joins can exceed `max_entries`.** `tournaments.ex:273` counts, then
  runs the (fee-charging) hook, then inserts.
- [x] **Quest contention sleeps inside the transaction.** `quests.ex:497` — 25 retries
  with sleeps while holding the single SQLite writer.
- [x] **Ready-check member removal can revive a failed check.** `ready_checks.ex:485`
  does not re-read inside the lock.
- [x] **Presigned S3 uploads do not bind content type.** `storage/s3.ex:67`;
  `uploads.ex:104` never corrects the stored type.
- [x] **Public storage route serves every key.** `router/shared.ex:222` — no prefix
  allowlist; admin uploader writes arbitrary paths.
- [x] **One malformed plugin env var stops the node booting.** `plugin_manager.ex:277`
  asserts `{:ok, cast} =`; declaration callbacks also run with no timeout.
- [x] **Cancelled invite can still be accepted.** `parties.ex:505`, `groups/invites.ex:196`
  never re-validate inside the join; the marking update discards its row count.
- [x] **One group message writes one notification row per member** (default cap 10,000),
  preloading full user rows. `chat.ex:284`, `groups.ex:253`.
- [x] **`Uploads.confirm` accepts `..` segments.** `uploads.ex:86` checks only the prefix.
- [x] **Push token registration reassigns a token to whoever posts it.** `push.ex:122`.

## Low

- [x] **Unclamped leaderboard `limit`;** membership check missing on chat report;
  `String.to_integer` on user input returns 500. `leaderboard_controller.ex:425`,
  `chat_controller.ex:538`, `lobbies.ex:1627`, `groups.ex:509`, `parties.ex:1094`.
- [x] **Unknown channel events unthrottled and logged verbatim.** `lobby_channel.ex:109`
  and five others; mesh signaling relays unbounded payloads.
- [x] **Read cursor not monotonic** (`chat.ex:597`); **chat notifications collide on
  title** (`chat.ex:275`, `notifications.ex:594`) when a group is named to match.
- [x] **Slow-request log records OAuth `code` and `state`.** `request_timer.ex:105`
  redacts password/token/secret but not `code`/`state`.
- [x] **`Settings.read_env` logs the raw value on a failed cast** regardless of
  `secret: true` (`settings.ex:170`); `cast(raw, :atom)` uses `String.to_atom` (`:202`).
- [x] **Client log messages allow ANSI/control characters** into the rotating log file
  (`client_logs.ex:283`); byte cap applied with `String.slice` on graphemes.

---

## Round 2

Findings the audits reported that the first pass did not carry into this file.
Recorded here in full rather than dropped.

### Security

- [x] **Apple JWS: marker OIDs never checked.** `providers/apple.ex:349,366` validates
  the chain to Apple Root CA - G3 but not the leaf marker `1.2.840.113635.100.6.11.1`
  or the intermediate `1.2.840.113635.100.6.2.1`. Apple issues other ECC certs under
  the same root, so one of those could sign an accepted JWS.
- [x] **Apple bundle id unchecked when unconfigured.** `providers/apple.ex:140` returns
  `:ok` with no bundle id, and `verify_notification/1` never checks `data.bundleId`.
  A JWS-only deployment gets no warning.
- [x] **Hidden lobbies joinable by id, and `/users/:id` leaks `lobby_id`/`party_id`.**
  `user_controller.ex:150`, `lobbies.ex` `do_join` has no `is_hidden` check although
  `show/2` deliberately 404s them.
- [x] **Mesh signaling: any peer may `broadcast_offer`, payload unvalidated.**
  `signaling.ex:265`, `signaling_channel.ex:206`. One peer fans out to every other,
  and `sdp`/`candidate` are relayed without a size or type check.
- [x] **`DELETE /api/v1/me` needs no re-authentication** (`me_controller.ex:349`),
  while changing a password does.
- [x] **Registration `validate` is an unthrottled email-existence oracle.**
  `registration.ex:83` runs `unsafe_validate_unique` on every keystroke.
- [~] **Friend notifications carry an arbitrary `icon_url`,** and one friend can fill
  a victim's `max_notifications_per_user` with distinct titles. `notifications.ex:408`.
  The `icon_url` is length-capped and only reaches people who accepted the friendship;
  the per-sender quota needed to close the exhaustion half is a behaviour decision
  (how many notifications may one friend hold), so it is left for you to set.
- [x] **Stripe success/cancel URLs unvalidated** (`stripe.ex:12`); **Steam `steam_id`
  never compared with `user.steam_id`** (`steam.ex:31`).
- [x] **Client-supplied `access_token` overrides the service credential** on
  `/validate/google` (`providers/google.ex:218`).
- [x] **Admin can demote or delete the last admin, including themselves**
  (`admin/user_controller.ex:61`); the admin "confirmed" toggle writes a field
  `admin_changeset` does not cast, so it silently does nothing.
- [x] **`auth_controller.ex` catch-all logs raw callback params** including `code`
  and `state`, bypassing `filter_parameters`.

### Correctness

- [x] **OAuth session polling sits in the 10/min auth bucket.** `rate_limiter.ex:164`.
  The shipped client polls every 2s for 60s, so any OAuth login slower than ~18s
  fails with a timeout on production defaults.
- [~] **Google pending purchases produce two rows.** `providers/google.ex:94` keys on
  `orderId || token`. The second fulfilment is now blocked by the original-transaction
  ownership check and the `FOR UPDATE` in `fulfill_purchase/2`, so no double grant —
  but the duplicate *row* remains. Fixing it properly means keying Google on the
  purchase token throughout, which changes the dedupe key for existing rows and wants
  a backfill.
- [x] **Refunds are handled coarsely:** `refund.created`/`updated` (including failed
  and cancelled) and partial `charge.refunded` all fully revoke (`payments.ex:1200`).
  Upstream error tuples are echoed to callers (`payment_controller.ex:279`).
- [x] **Chat notifications collide on title.** `chat.ex:275`, `notifications.ex:594`:
  a group or lobby named to match the friend-DM title merges into its slot, and the
  routing metadata is overwritten.
- [x] **`create_party` and `do_join_party` lock different keys** (`parties.ex:320` vs
  `:871`), so a user can end up leading a party they are not in.
- [x] **`leave_group` broadcasts before commit** (`groups.ex:798`), and the cache
  version bump can land pre-commit.
- [x] **`after_draw/2` broadcasts inside the open draw transaction**
  (`tournaments.ex:596`), skipping the module's own `defer/1` machinery.
- [x] **Presence: a disconnect racing a reconnect can leave a live user offline
  forever.** `user_channel.ex` terminate + `presence.ex:48` `last_socket?/1` reads
  the local tracker shard only.

### Performance

- [x] **Plugin hooks still run inside transactions at several sites** with the 60s
  default timeout (`groups/shared.ex`, `lobbies.ex` join, `parties.ex`,
  `tournaments.ex`, `push.ex:593`). Matchmaking was fixed in round 1.
- [x] **Per-user leaderboard rank is an O(N) count with an OR predicate no index
  serves** (`leaderboards.ex:877`); the paged list orders on `inserted_at` while the
  index carries `updated_at`.
- [x] **Signaling re-reads the lobby per subscriber per presence diff**
  (`signaling_channel.ex:395`), and `write_webrtc_config/2` broadcasts without
  preloaded memberships.
- [~] **Group chat notification fanout is still one insert per member.** Round 1 cut
  the preload of every member's full user row, which was the bulk of it, and the whole
  fanout already runs off the request path inside `Gamend.Async.run`. Batching the
  upserts is awkward because each carries an adapter-specific JSON increment, and
  capping the fanout for very large groups would change who gets notified — a product
  decision, not a cleanup.

### Repository hygiene

- [x] **Build artifacts tracked in git:** nine `.br` files under `priv/static/`
  (so `cache_manifest.json.br` shows modified after every build) and an empty
  `apps/gamend_web/game_server_test.db`.
- [~] **Three crash dumps, ~37 MB, untracked but present** in the working tree
  (`erl_crash.dump` and one under each app). Already covered by `.gitignore`, so they
  never reach the repository — this is local disk only. Left in place: they are yours,
  not mine to delete, and they record boot failures from July and August.
- [x] **Three dependency updates available** (oban_web, open_api_spex,
  phoenix_live_dashboard). CI's `check-outdated` job fails on "Update possible".

---

## Verified sound (do not re-audit)

Wallet debits are a single conditional update. Quest progress uses an optimistic lock
with re-merge; claiming is a conditional transition. Idempotency keys are backed by
unique indexes, and the SQLite adapter maps the violation to a named constraint.
Score submission, wallet and inventory mutation have no client endpoint. Every
`/api/v1/admin/*` route is behind the admin pipeline, and ownership is checked in the
contexts rather than only the controllers. Stripe signature verification uses the raw
body with a timestamp tolerance and constant-time compare. Local storage paths reject
`.`/`..`/`/` per segment. Index coverage across the 68 migrations matches the real query
shapes. Password hashing is Argon2id with a bcrypt fallback and a dummy verify. No user
input reaches `String.to_atom` in channels, the event codec, signaling or KV. Chat
moderation matches via a compiled binary pattern, not regexes.
