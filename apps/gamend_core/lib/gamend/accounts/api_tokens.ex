defmodule Gamend.Accounts.ApiTokens do
  @moduledoc """
  Personal API tokens: long-lived bearer tokens for scripts and CI.

  An access token from `POST /api/v1/login` lasts fifteen minutes and needs a
  password, which suits a game client and nothing that runs unattended — and an
  account made with a social login has no password at all. A personal token is
  created once on the settings page, sent as `Authorization: Bearer
  gamend_pat_…` to any API route that takes an access token, and lasts until it
  expires or is revoked.

  ## What is kept

  Only a SHA-256 of the token, under a unique index: a request is one indexed
  lookup, and the table holds nothing a client could send. The token is shown
  once, at creation. `hint` is its first few characters, so a list can say
  which token a CI secret holds without holding it.

  ## When a token stops working

  - It expires (`expires_at/1`: its own `expires_at`, or `auth.api_token_max_days`
    after creation when that is sooner), or its owner revokes it.
  - Its owner changes their password or email, or signs out everywhere: each
    bumps `users.token_version`, and a token remembers the version it was made
    under. A stolen session therefore cannot leave a token behind that
    survives the password reset that ends it.
  - The account is deactivated — the same check an access token gets, in
    `GamendWeb.Auth.Guardian.resource_from_claims/1`.

  Tokens are made only through the settings page, never through the API, so a
  leaked token cannot mint another. `Gamend.Retention` prunes expired and
  superseded rows.
  """

  import Ecto.Query

  alias Gamend.Accounts.ApiToken
  alias Gamend.Accounts.User
  alias Gamend.Repo

  @prefix "gamend_pat_"
  @hint_length 6
  # A token used in a tight loop would otherwise write its row on every call.
  @touch_every_seconds 60

  @doc "What every personal token starts with; how the auth plug tells one from a JWT."
  @spec prefix() :: String.t()
  def prefix, do: @prefix

  @doc "Whether `value` is shaped like a personal token."
  @spec token?(term()) :: boolean()
  def token?(value) when is_binary(value), do: String.starts_with?(value, @prefix)
  def token?(_value), do: false

  @doc """
  Create a token for `user`. Answers the token itself — the only time it
  exists outside the caller — and the stored row.

  `attrs` takes `name` and `expires_in_days`, one of `ApiToken.expiry_choices/0`
  (30, 90, 365, or nil for none, unless `auth.api_token_max_days` caps them).
  Refused with `:limit_reached` past `Gamend.Limits` `max_api_tokens_per_user`.
  """
  @spec create(User.t(), map()) ::
          {:ok, String.t(), ApiToken.t()} | {:error, Ecto.Changeset.t() | :limit_reached}
  def create(%User{} = user, attrs) do
    if count(user.id) >= Gamend.Limits.get(:max_api_tokens_per_user) do
      {:error, :limit_reached}
    else
      secret = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      token = @prefix <> secret

      %ApiToken{
        user_id: user.id,
        token_hash: hash(token),
        hint: String.slice(secret, 0, @hint_length),
        token_version: user.token_version || 0
      }
      |> ApiToken.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, row} -> {:ok, token, row}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  The owner and row of a presented token, or `:error` when it is unknown,
  expired, or older than its owner's last credential change.
  """
  @spec verify(String.t()) :: {:ok, User.t(), ApiToken.t()} | :error
  def verify(token) when is_binary(token) do
    with true <- token?(token),
         %ApiToken{user: %User{} = user} = row <- get_by_hash(hash(token)),
         true <- live?(row, user) do
      {:ok, user, row}
    else
      _ -> :error
    end
  end

  def verify(_token), do: :error

  defp get_by_hash(digest) do
    Repo.one(from(t in ApiToken, where: t.token_hash == ^digest, preload: :user))
  end

  defp live?(%ApiToken{} = row, %User{} = user) do
    row.token_version == (user.token_version || 0) and not expired?(row)
  end

  @doc """
  When the token stops working on its own: its `expires_at`, or
  `auth.api_token_max_days` after it was made when that comes first. nil when
  it never expires. The cap reaches tokens made before it was set.
  """
  @spec expires_at(ApiToken.t()) :: DateTime.t() | nil
  def expires_at(%ApiToken{expires_at: own, inserted_at: made}) do
    case ApiToken.max_days() do
      nil ->
        own

      days ->
        capped = DateTime.add(made, days, :day)
        if own && DateTime.before?(own, capped), do: own, else: capped
    end
  end

  @doc "Whether the token's own lifetime has run out."
  @spec expired?(ApiToken.t()) :: boolean()
  def expired?(%ApiToken{} = row) do
    case expires_at(row) do
      nil -> false
      at -> DateTime.compare(at, DateTime.utc_now()) != :gt
    end
  end

  @doc """
  Whether the owner's password or email changed since the token was made.
  Such a token is dead; the settings page says so rather than listing it as
  working.
  """
  @spec superseded?(ApiToken.t(), User.t()) :: boolean()
  def superseded?(%ApiToken{token_version: version}, %User{token_version: current}),
    do: version != (current || 0)

  @doc """
  Record a use, at most once a minute per token, off the request path: the
  caller is an authenticated request and should not wait on a write.
  """
  @spec touch(ApiToken.t()) :: :ok
  def touch(%ApiToken{id: id, last_used_at: last}) do
    now = DateTime.utc_now(:second)

    if is_nil(last) or DateTime.diff(now, last) >= @touch_every_seconds do
      Gamend.Async.run(fn ->
        cutoff = DateTime.add(now, -@touch_every_seconds, :second)

        Repo.update_all(
          from(t in ApiToken,
            where: t.id == ^id and (is_nil(t.last_used_at) or t.last_used_at <= ^cutoff)
          ),
          set: [last_used_at: now]
        )
      end)
    end

    :ok
  end

  @doc "A user's tokens, newest first."
  @spec list(String.t(), keyword()) :: [ApiToken.t()]
  def list(user_id, opts \\ []) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    from(t in ApiToken,
      where: t.user_id == ^user_id,
      order_by: [desc: t.inserted_at, desc: t.id],
      limit: ^page_size,
      offset: ^((page - 1) * page_size)
    )
    |> Repo.all()
  end

  @doc "Count for `list/2`'s pagination."
  @spec count(String.t()) :: non_neg_integer()
  def count(user_id) when is_binary(user_id) do
    Repo.one(from(t in ApiToken, where: t.user_id == ^user_id, select: count(t.id))) || 0
  end

  @doc "Revoke one of the user's tokens. It stops working on the next request."
  @spec revoke(String.t(), String.t()) :: {:ok, ApiToken.t()} | {:error, :not_found}
  def revoke(user_id, id) when is_binary(user_id) and is_binary(id) do
    case Repo.one(from(t in ApiToken, where: t.user_id == ^user_id and t.id == ^id)) do
      nil -> {:error, :not_found}
      row -> Repo.delete(row)
    end
  end

  @doc """
  Rows no request can use any more: past `expires_at`, or made under an older
  `token_version` than their owner's. For `Gamend.Retention`.
  """
  #
  # The join sits in a subquery so the outer query is a plain one on
  # `api_tokens`: retention deletes through it, and SQLite has no
  # `DELETE … JOIN`.
  @spec dead_query() :: Ecto.Query.t()
  def dead_query do
    now = DateTime.utc_now()

    dead =
      dynamic(
        [t, u],
        (not is_nil(t.expires_at) and t.expires_at <= ^now) or
          t.token_version != coalesce(u.token_version, 0)
      )

    dead =
      case ApiToken.max_days() do
        nil -> dead
        days -> dynamic([t], ^dead or t.inserted_at <= ^DateTime.add(now, -days, :day))
      end

    dead_ids =
      from(t in ApiToken,
        join: u in User,
        on: u.id == t.user_id,
        where: ^dead,
        select: t.id
      )

    from(t in ApiToken, where: t.id in subquery(dead_ids))
  end

  defp hash(token), do: :crypto.hash(:sha256, token)
end
