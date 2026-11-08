# `Gamend.Secrets.Secret`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/secrets/secret.ex#L1)

One encrypted value, and the metadata a person needs to manage something
they can never read back.

The struct is safe to hand to a template: it holds ciphertext, not a secret.
`Gamend.Secrets.fetch/3` is the only thing that opens one.

# `t`

```elixir
@type t() :: %Gamend.Secrets.Secret{
  __meta__: term(),
  byte_size: term(),
  ciphertext: term(),
  created_by_id: term(),
  expires_at: term(),
  id: term(),
  inserted_at: term(),
  iv: term(),
  key_id: term(),
  kind: term(),
  last_used_at: term(),
  name: term(),
  scope: term(),
  scope_id: term(),
  tag: term(),
  updated_at: term()
}
```

# `expired?`

```elixir
@spec expired?(t(), DateTime.t()) :: boolean()
```

Whether this secret has passed the expiry it was given.

Nothing enforces it — a certificate that expired yesterday still decrypts,
and the signer will fail with whatever the platform's tooling says. This is
for telling somebody *before* that happens.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
