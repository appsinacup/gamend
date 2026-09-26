# `Gamend.HTTP`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/http.ex#L1)

`Req` with the declared timeout and retries, for the calls core makes to other
services while a player waits: payment receipt checks (Apple, Google Play,
Steam), OAuth code exchanges, Google ID-token checks and avatar mirroring.

Req's own defaults suit a script, not a request handler: 15 seconds a try
and, for a GET, three retries with backoff, so one slow provider held a login
or a purchase check open for about a minute. Here each try waits
`client_timeout_ms` and a failed GET is retried `client_retries` times. A POST
is not retried, as in Req.

`get/2` and `post/2` take what `Req.get/2` and `Req.post/2` take, so this
module drops in wherever a module takes an injectable HTTP client. Options a
caller passes win over the declared ones.

# `get`

```elixir
@spec get(String.t() | URI.t(), keyword()) ::
  {:ok, Req.Response.t()} | {:error, Exception.t()}
```

`Req.get/2` with the declared timeout and retries.

# `options`

```elixir
@spec options(keyword()) :: keyword()
```

The declared timeout and retry options, with `opts` over them.

`config :gamend_core, Gamend.HTTP, req_options: [...]` is merged in too, so
a test can route every provider call through a `Req.Test` stub. Empty in prod.

# `post`

```elixir
@spec post(String.t() | URI.t(), keyword()) ::
  {:ok, Req.Response.t()} | {:error, Exception.t()}
```

`Req.post/2` with the declared timeout and retries.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
