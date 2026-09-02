# `Gamend.Hooks.Default`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks.ex#L1417)

Default no-op implementation for Gamend.Hooks

# `before_kv_get`

Default implementation for `before_kv_get/2`.

Scope-aware, not blanket-public. A global entry (no `user_id`, no `lobby_id`)
is `:public`, which is what makes a shared config or welcome value readable by
everyone. A read that *names* a user or lobby defaults to
`:owner_or_lobby_member`, so the caller has to be that user or in that lobby.

It used to return `:public` unconditionally, and `kv_access_allowed?/4` grants
a `:public` read without looking at who is asking — so with no plugin
overriding this hook, `GET /api/v1/kv/save_data?user_id=<someone else>` (and
the `kv:subscribe` channel event, which then streamed every later write)
returned another player's entries. Saves and progression live there.

A game that genuinely wants cross-player reads implements this hook and
returns `:public` for those keys.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
