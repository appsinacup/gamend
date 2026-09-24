# `Gamend.OAuth.Exchanger`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/oauth/exchanger.ex#L1)

Default implementation for exchanging OAuth codes with providers.

This module is intentionally small and works with the Req library.
Tests may replace the exchanger via application config for easier stubbing.

# `exchange_apple_code`

```elixir
@spec exchange_apple_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
  {:ok, map()} | {:error, term()}
```

# `exchange_discord_code`

```elixir
@spec exchange_discord_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
  {:ok, map()} | {:error, term()}
```

# `exchange_facebook_code`

```elixir
@spec exchange_facebook_code(
  String.t(),
  String.t(),
  String.t(),
  String.t(),
  keyword()
) ::
  {:ok, map()} | {:error, term()}
```

# `exchange_github_code`

```elixir
@spec exchange_github_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
  {:ok, map()} | {:error, term()}
```

# `exchange_google_code`

```elixir
@spec exchange_google_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
  {:ok, map()} | {:error, term()}
```

# `exchange_steam_code`

```elixir
@spec exchange_steam_code(String.t()) :: {:ok, map()} | {:error, term()}
```

# `exchange_steam_ticket`

```elixir
@spec exchange_steam_ticket(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

Verify a Steam auth ticket using ISteamUserAuth/AuthenticateUserTicket/v1

Expects a ticket (binary blob) returned by the Steamworks client SDK. Returns
{:ok, user_info} on successful verification or {:error, reason} on failure.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
