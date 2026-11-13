# `Gamend.Secrets`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/secrets.ex#L1)

Somewhere to keep a credential that belongs to a *customer*.

`Gamend.Settings` is the operator's configuration: it comes from the
environment, and `secret: true` only masks a value on the admin page. That is
the right shape for a webhook secret the operator sets once. It is the wrong
shape for a signing certificate a studio uploads, a store API key, or
anything else a host holds on somebody's behalf — those are per-customer,
arrive at runtime, and must survive a database dump landing on a laptop.

## Where the bytes are, and where the key is

Rows live in the `secrets` table. The key does not: it is a setting, read
from the environment, so the ciphertext and the thing that opens it are never
in the same place. A leaked backup, a read replica, a SQL injection or a
contractor with database access all yield ciphertext and nothing else.

What this does **not** protect against is the application being compromised.
Code running here can decrypt, necessarily — the signer has to. Anything
claiming otherwise is describing a different product.

## The shape

  * **AES-256-GCM**, a fresh random IV per write. GCM because it authenticates
    as well as encrypts: a row edited in the database fails to open rather
    than opening as something else.
  * **The owner and the name are the additional authenticated data.** A
    ciphertext lifted out of one project's row and dropped into another's
    then fails to decrypt, instead of quietly signing the wrong studio's
    build with the wrong certificate. This is the part worth reading twice.
  * **Keys are named.** `key_id` records which key wrote a row, so rotating
    is: add a key, make it current, let `rotate/0` rewrite rows in the
    background. Old rows stay readable in the meantime rather than the whole
    table needing one transaction.

## Configuration

    GAMEND_SECRETS_KEYS="v2:<base64>,v1:<base64>"

Comma-separated `id:key` pairs, each key 32 bytes base64-encoded. **The first
is current** and is what new writes use; the rest exist so rows written
before a rotation can still be read. Generate one with:

    :crypto.strong_rand_bytes(32) |> Base.encode64()

Unset, every call answers `{:error, :no_key}`. That is deliberate: a host
that has not configured a key should fail loudly on the first write rather
than store a credential in a way it cannot honour later. A malformed first
pair counts as unset: the next pair is an older key, and writing under it
would quietly undo a rotation. Any malformed pair is logged, by its position.

# `config`

```elixir
@spec config(atom()) :: term()
```

Read one of this group's settings.

# `configured?`

```elixir
@spec configured?() :: boolean()
```

Whether a key is configured at all, for a setup page to ask.

# `delete`

```elixir
@spec delete(String.t(), String.t(), String.t()) :: :ok
```

Forget one secret. Immediate, not retention-swept.

# `delete_all`

```elixir
@spec delete_all(String.t(), String.t()) :: non_neg_integer()
```

Forget everything one owner had. What deleting the owner must call.

# `fetch`

```elixir
@spec fetch(String.t(), String.t(), String.t()) ::
  {:ok, binary()} | {:error, :not_found | :undecryptable | :no_key}
```

The plaintext of one secret.

`{:error, :not_found}` when there is none, and `{:error, :undecryptable}`
when there is a row that will not open — a key that is no longer configured,
or a row that has been tampered with. Those two are deliberately different:
the first is a question about setup, the second is a question about trust.

# `get`

```elixir
@spec get(String.t(), String.t(), String.t()) :: Gamend.Secrets.Secret.t() | nil
```

One secret's metadata, or `nil`.

# `list`

```elixir
@spec list(String.t(), String.t()) :: [Gamend.Secrets.Secret.t()]
```

Every secret an owner has, as metadata.

Never the values — this is what a page renders, and a page that can render a
secret is a secret that ends up in a screenshot.

# `put`

```elixir
@spec put(String.t(), String.t(), String.t(), binary(), keyword()) ::
  {:ok, Gamend.Secrets.Secret.t()} | {:error, :no_key | Ecto.Changeset.t()}
```

Store `value` under `name` for one owner, replacing whatever was there.

`opts` takes `:kind` (free-form, for the UI to label a field), `:expires_at`
and `:created_by_id`.

# `rotate`

```elixir
@spec rotate(pos_integer()) ::
  {:ok,
   %{
     moved: non_neg_integer(),
     stuck: non_neg_integer(),
     skipped: non_neg_integer()
   }}
  | {:error, :no_key}
```

Re-encrypt every row not already written under the current key.

Run after adding a key to the front of the setting. One call walks the whole
table, `batch` rows read at a time and each rewritten on its own. The old key
stays configured until this reports none stuck — removing it earlier is how a
certificate becomes unreadable.

Answers how many rows moved, how many could not be opened at all, and how
many were skipped because a `put/5` or `delete/3` changed them meanwhile
(a `put` writes under the current key already).

# `use`

```elixir
@spec use(String.t(), String.t(), String.t()) ::
  {:ok, binary()} | {:error, :not_found | :undecryptable | :no_key}
```

Like `fetch/3`, and notes that the secret was used.

What the signer calls. `last_used_at` is the column that answers "is this
certificate still doing anything" a year from now, which is the question
behind every credential nobody dares delete.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
