defmodule Gamend.Secrets do
  @moduledoc """
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
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :secrets,
    label: "Secrets"

  import Ecto.Query

  alias Gamend.Repo
  alias Gamend.Secrets.Secret

  require Logger

  @cipher :aes_256_gcm
  @iv_size 12
  @tag_size 16
  @key_size 32

  setting(:keys, :string,
    secret: true,
    doc:
      "Comma-separated id:key pairs for encrypting customer secrets, each key 32 bytes base64. The first is used for new writes; the rest let rows written before a rotation still be read. Unset disables the store."
  )

  @doc "Read one of this group's settings."
  @spec config(atom()) :: term()
  def config(key) when is_atom(key), do: Gamend.Settings.get(__MODULE__, key)

  @doc """
  Store `value` under `name` for one owner, replacing whatever was there.

  `opts` takes `:kind` (free-form, for the UI to label a field), `:expires_at`
  and `:created_by_id`.
  """
  @spec put(String.t(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, Secret.t()} | {:error, :no_key | Ecto.Changeset.t()}
  def put(scope, scope_id, name, value, opts \\ []) when is_binary(value) do
    with {:ok, {key_id, key}} <- current_key() do
      iv = :crypto.strong_rand_bytes(@iv_size)
      aad = aad(scope, scope_id, name)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(@cipher, key, iv, value, aad, true)

      attrs = %{
        scope: scope,
        scope_id: scope_id,
        name: name,
        ciphertext: ciphertext,
        iv: iv,
        tag: tag,
        key_id: key_id,
        kind: Keyword.get(opts, :kind),
        byte_size: byte_size(value),
        expires_at: Keyword.get(opts, :expires_at),
        created_by_id: Keyword.get(opts, :created_by_id)
      }

      case get(scope, scope_id, name) do
        nil -> %Secret{}
        existing -> existing
      end
      |> Secret.changeset(attrs)
      |> Repo.insert_or_update()
    end
  end

  @doc """
  The plaintext of one secret.

  `{:error, :not_found}` when there is none, and `{:error, :undecryptable}`
  when there is a row that will not open — a key that is no longer configured,
  or a row that has been tampered with. Those two are deliberately different:
  the first is a question about setup, the second is a question about trust.
  """
  @spec fetch(String.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, :not_found | :undecryptable | :no_key}
  def fetch(scope, scope_id, name) do
    case get(scope, scope_id, name) do
      nil -> {:error, :not_found}
      secret -> open(secret)
    end
  end

  @doc """
  Like `fetch/3`, and notes that the secret was used.

  What the signer calls. `last_used_at` is the column that answers "is this
  certificate still doing anything" a year from now, which is the question
  behind every credential nobody dares delete.
  """
  @spec use(String.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, :not_found | :undecryptable | :no_key}
  def use(scope, scope_id, name) do
    with {:ok, value} <- fetch(scope, scope_id, name) do
      now = DateTime.utc_now()

      Secret
      |> where([s], s.scope == ^scope and s.scope_id == ^scope_id and s.name == ^name)
      |> Repo.update_all(set: [last_used_at: now, updated_at: now])

      {:ok, value}
    end
  end

  @doc """
  Every secret an owner has, as metadata.

  Never the values — this is what a page renders, and a page that can render a
  secret is a secret that ends up in a screenshot.
  """
  @spec list(String.t(), String.t()) :: [Secret.t()]
  def list(scope, scope_id) do
    Secret
    |> where([s], s.scope == ^scope and s.scope_id == ^scope_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc "One secret's metadata, or `nil`."
  @spec get(String.t(), String.t(), String.t()) :: Secret.t() | nil
  def get(scope, scope_id, name),
    do: Repo.get_by(Secret, scope: scope, scope_id: scope_id, name: name)

  @doc "Forget one secret. Immediate, not retention-swept."
  @spec delete(String.t(), String.t(), String.t()) :: :ok
  def delete(scope, scope_id, name) do
    Secret
    |> where([s], s.scope == ^scope and s.scope_id == ^scope_id and s.name == ^name)
    |> Repo.delete_all()

    :ok
  end

  @doc "Forget everything one owner had. What deleting the owner must call."
  @spec delete_all(String.t(), String.t()) :: non_neg_integer()
  def delete_all(scope, scope_id) do
    {count, _} =
      Secret
      |> where([s], s.scope == ^scope and s.scope_id == ^scope_id)
      |> Repo.delete_all()

    count
  end

  @doc """
  Re-encrypt every row not already written under the current key.

  Run after adding a key to the front of the setting. One call walks the whole
  table, `batch` rows read at a time and each rewritten on its own. The old key
  stays configured until this reports none stuck — removing it earlier is how a
  certificate becomes unreadable.

  Answers how many rows moved, and how many could not be opened at all.
  """
  @spec rotate(pos_integer()) ::
          {:ok, %{moved: non_neg_integer(), stuck: non_neg_integer()}} | {:error, :no_key}
  def rotate(batch \\ 100) do
    with {:ok, {key_id, _key}} <- current_key() do
      {:ok, rotate_after(nil, key_id, batch, %{moved: 0, stuck: 0})}
    end
  end

  @doc "Whether a key is configured at all, for a setup page to ask."
  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _}, current_key())

  ## Internals

  # Forward by id. A row that will not open stays stale, so reading the first
  # page again would bring it back every time and never reach the rows behind.
  defp rotate_after(cursor, key_id, batch, tally) do
    rows = stale_rows(cursor, key_id, batch)
    tally = Enum.reduce(rows, tally, &rotate_row/2)

    if length(rows) < batch do
      tally
    else
      rotate_after(List.last(rows).id, key_id, batch, tally)
    end
  end

  defp stale_rows(cursor, key_id, batch) do
    Secret
    |> where([s], s.key_id != ^key_id)
    |> after_id(cursor)
    |> order_by([s], asc: s.id)
    |> limit(^batch)
    |> Repo.all()
  end

  defp after_id(query, nil), do: query
  defp after_id(query, id), do: where(query, [s], s.id > ^id)

  defp rotate_row(%Secret{} = secret, tally) do
    case open(secret) do
      {:ok, value} ->
        {:ok, _} =
          put(secret.scope, secret.scope_id, secret.name, value,
            kind: secret.kind,
            expires_at: secret.expires_at,
            created_by_id: secret.created_by_id
          )

        %{tally | moved: tally.moved + 1}

      {:error, _reason} ->
        %{tally | stuck: tally.stuck + 1}
    end
  end

  defp open(%Secret{} = secret) do
    with {:ok, key} <- key_for(secret.key_id) do
      aad = aad(secret.scope, secret.scope_id, secret.name)

      case :crypto.crypto_one_time_aead(
             @cipher,
             key,
             secret.iv,
             secret.ciphertext,
             aad,
             secret.tag,
             false
           ) do
        :error -> {:error, :undecryptable}
        plaintext -> {:ok, plaintext}
      end
    end
  end

  # The owner and the name, bound into the ciphertext. Moving a row between
  # owners, or renaming it in the database, makes it undecryptable rather than
  # making it somebody else's secret.
  defp aad(scope, scope_id, name), do: "#{scope}/#{scope_id}/#{name}"

  # The first entry or none: falling through to the next well-formed one would
  # keep writing under the key a rotation just retired.
  defp current_key do
    case keys() do
      [{id, key} | _rest] -> {:ok, {id, key}}
      _none_or_malformed -> {:error, :no_key}
    end
  end

  defp key_for(key_id) do
    case Enum.find(keys(), &match?({^key_id, _key}, &1)) do
      {_id, key} -> {:ok, key}
      nil -> {:error, :undecryptable}
    end
  end

  # Parsed on every call rather than cached: this is not hot, and a cache is
  # one more place a key sits in memory after the setting that held it changed.
  defp keys do
    config(:keys)
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.with_index(1)
    |> Enum.map(&parse_key/1)
  end

  defp parse_key({pair, position}) do
    with [id, encoded] <- String.split(String.trim(pair), ":", parts: 2),
         {:ok, key} <- Base.decode64(String.trim(encoded)),
         true <- byte_size(key) == @key_size do
      {String.trim(id), key}
    else
      _malformed ->
        # By position: what was typed here may be the key itself.
        Logger.error("GAMEND_SECRETS_KEYS entry #{position} is malformed and ignored")
        :malformed
    end
  end

  @doc false
  # Sizes the table and the tests both refer to, in one place.
  def sizes, do: %{iv: @iv_size, tag: @tag_size, key: @key_size}
end
