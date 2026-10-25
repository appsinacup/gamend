# `Gamend.GitHub.API`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/github/api.ex#L1)

The GitHub REST calls a GitHub App makes, and the credentials that make
them.

A GitHub App speaks with three different tokens and it is worth keeping
them apart by name:

  * the **App JWT**, signed here with the App's private key, ten minutes
    long, and good only for asking about installations and minting the
    next kind;
  * an **installation token**, one hour, scoped to the repositories one
    installation was granted, and what clones a private repository and
    writes a check run;
  * a **user token**, from the OAuth code a person brings back from
    GitHub, used exactly once to ask which installations they may see.

Nothing here decides who may do what; that is `Gamend.GitHub`. This module
only knows how to ask. Every call merges `:github_req_options` from
`:gamend_core`'s environment, which is how a test points it at a
`Req.Test` stub.

# `result`

```elixir
@type result() :: {:ok, term()} | {:error, term()}
```

# `token`

```elixir
@type token() :: String.t()
```

# `app_jwt`

```elixir
@spec app_jwt(String.t(), String.t() | nil) ::
  {:ok, token()} | {:error, :invalid_private_key}
```

A JWT the App signs for itself. `iat` sits a minute in the past because
GitHub rejects a token whose clock is ahead of its own, and `exp` stays
under the ten-minute ceiling.

`{:error, :invalid_private_key}` when the configured key is not an RSA
private key in PEM. That is the operator's to fix, and every caller is on a
path that has to end (a checkout, a check run), so it is an answer rather
than a raise that left the job that asked running.

# `convert_manifest`

```elixir
@spec convert_manifest(String.t()) :: result()
```

Turn the code GitHub hands back from a manifest form into the App: its id,
slug, client pair, webhook secret and private key, in one answer. No
credential goes with it: the code is the credential, and it is good once,
for an hour.

# `create_check_run`

```elixir
@spec create_check_run(token(), String.t(), map()) :: result()
```

Create a check run on `repo` (`owner/name`). Answers GitHub's object.

# `exchange_code`

```elixir
@spec exchange_code(String.t(), String.t(), String.t(), String.t()) ::
  {:ok, token()} | {:error, term()}
```

The user token an OAuth code proves. Nothing about the person is read here.

# `installation`

```elixir
@spec installation(token(), integer()) :: result()
```

One installation, as the App sees it: its account and what it may reach.

# `installation_repositories`

```elixir
@spec installation_repositories(token()) :: {:ok, [map()]} | {:error, term()}
```

Every repository an installation was granted, across all its pages.

A hundred per page and a page cap that no real installation reaches: a
token minted for one organisation cannot list somebody else's repositories
anyway, so a runaway here costs requests, never data.

# `installation_token`

```elixir
@spec installation_token(token(), integer()) ::
  {:ok, %{token: token(), expires_at: DateTime.t()}} | {:error, term()}
```

Mint an installation token. Answers the token and when it expires, so the
caller can cache it for exactly as long as it is worth caching.

# `update_check_run`

```elixir
@spec update_check_run(token(), String.t(), integer(), map()) :: result()
```

Overwrite a check run's state. Every field named is replaced.

# `user_installations`

```elixir
@spec user_installations(token()) :: {:ok, [map()]} | {:error, term()}
```

The installations this person may see, as GitHub answers the question.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
