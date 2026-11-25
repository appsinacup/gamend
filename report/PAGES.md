# Pages, admin and docs — open items

From the 2026-09-18 proofread of every page, admin screen and doc in this repo.
About 250 findings were fixed in the same pass; these are the ones that need a
decision, touch code outside the page, or could not be verified.

## Bugs found while proofreading

- [ ] **Party leader can join a hidden lobby.** `Parties.join_lobby_with_party`
  has no hidden check; a solo join refuses with `:not_found` unless
  `bypass_hidden`.
- [ ] **Hidden-lobby join status disagrees.** `Lobbies.do_join` returns
  `:not_found`, `LobbyController` maps it to 403 `cannot_join`. The docs now
  say 403; pick one.
- [ ] **Lobby API cannot clear a password.** `Lobbies.maybe_hash_password/1`
  hashes `""`, so the API's "empty string clears it" sets a hash of the empty
  string instead. (The admin page now has its own "remove the password" box.)
- [ ] **Admin Add Member on a party skips the capacity check.**
- [ ] **Quests admin `parse_metadata` silently ignores invalid JSON** — the
  other admin forms now refuse it.
- [ ] **Matchmaking offline grace never applies.** It exists "so a brief
  disconnect keeps its queue position", but `UserChannel.terminate/2` cancels
  tickets at once. Product call: keep the grace (don't cancel on terminate) or
  drop it.
- [ ] **`ConnectionTracker` does not track `SignalingChannel`**, so the
  admin Connections totals exclude signaling (the page now says so).

## Needs a decision

- [ ] Legal pages (terms, privacy, data deletion) are English in all 30
  locales.
- [ ] Admin heading case is mixed (Title Case vs sentence case) across ~40
  pages.
- [ ] Groups admin: when a group has no admin besides the target, promote /
  demote / kick can only say so. A real override needs a new `Groups`
  function.
- [ ] "No results." is the empty state on lists that are not searches
  (`chat_live`, `groups_tab`) — needs per-list empty-state strings.
- [ ] "You're offline" also shows when the server restarts. The string is
  declared in the polyglot host too, so reword both together.
- [ ] Apple's brand rules may require "Sign in with Apple"; the button says
  "Log in with Apple" like every provider.
- [ ] Matchmaking admin: the match id is not a link, because
  `/admin/lobbies` takes no id filter. Add one to link it.

## Not verified

- [ ] Steam ticket login probably needs a Steamworks **publisher** Web API
  key, not the steamcommunity.com/dev key `30-steam-openid.md` describes.
- [ ] `20-apple-sign-in.md`: the optional `GAMEND_OAUTH_APPLE_IOS_CLIENT_ID`
  example does not match the bundle id in step 5.
- [ ] Signaling rate limits on the admin page copy the channel's fallbacks
  (300 / 150); they are not declared settings.

## Translations from this pass

- [ ] The 79 new or reworded strings per locale in `apps/gamend_web/priv/gettext`
  were filled by machine in all 28 locales and want a native reader.
- [~] 52 admin-only strings per locale (the new admin plurals) are left
  English on purpose: admin tooling is not translated.

## Stale text outside the pages

- [ ] `webrtc_lobby_hook` moduledoc names an `after_lobby_updated/1` that does
  not exist, and a comment says "Star" where the code sets mesh.
- [ ] `30-realtime.md` PartyChannel table omits the `ready_check_*` events the
  channel pushes.
- [ ] The AutoClose countdown text on the auth success page lives in
  `assets/js/app.js` and is not translatable; pass translated strings from
  `auth_success_live.ex` as data attributes.
