# `Gamend.Accounts.UsernameGenerator`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/username_generator.ex#L1)

Generates default usernames for new users.

OAuth signups get a slug of the provider display name ("Dragoș" →
`dragos-4821`); email and device signups get a random word from the
embedded list below (`sheep-4821`) — never anything derived from the
email address, which would let strangers guess it. The numeric suffix is
random, not a sequential discriminator, so there is no counter to
exhaust; callers retry with a higher `attempt` on collision, which widens
the suffix.

# `generate`

```elixir
@spec generate(map(), pos_integer()) :: String.t()
```

Generate a username candidate from registration attrs (string keys).

Uses `attrs["display_name"]` when it slugs to something usable, a random
word otherwise. Attempts beyond 3 widen the numeric suffix.

# `slug`

```elixir
@spec slug(term()) :: String.t() | nil
```

Best-effort slug of a display name in username format; `nil` when too
little survives. A name that transliterates to ASCII keeps doing so
(`Drágoș` -> `dragos`, easier to type); one that does not (`山田太郎`,
`Дмитрий`) keeps its own script, as long as it is a valid handle.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
