# `Gamend.Accounts.AvatarMirror`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/avatar_mirror.ex#L1)

Oban worker that mirrors a user's external (OAuth provider) avatar into our
own object storage, so avatars render from our storage/CDN instead of
hotlinking the provider.

Enqueued on sign-in whenever a user's avatar is still an external URL (see
`Gamend.Accounts.maybe_mirror_avatar/1`). Once mirrored the stored URL
lives under our own `avatars/<user_id>/` prefix, so the check short-circuits
and we never re-fetch an avatar we already host.

A *failed* mirror is a different matter from a finished one. Provider CDNs
rate-limit (Google answers 429 readily), so the download is retried with
backoff, and a run that exhausts its attempts does not poison the user
forever — the next sign-in enqueues a fresh job. Until one succeeds the
provider URL stays in `profile_url`, but nothing shows it: every page and
payload reads `User.public_avatar_url/1`, which answers nil for it, so the
player has the default icon instead of a hotlink to the provider.

A copy is a player's picture in public storage, unscreened, so a host that
closes `user_image_uploads` gets none (`enabled?/0`): nothing is enqueued, a
job already queued is cancelled, and the player has the default icon. Cancelled
rather than done, since a completed job would keep the same URL from being
mirrored once the gate opens again.

# `enabled?`

```elixir
@spec enabled?() :: boolean()
```

Whether a provider's picture may be copied: not while `GamendWeb.Features` has
`user_image_uploads` off. A flag of the web app, so it is on where that app is
not loaded.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
