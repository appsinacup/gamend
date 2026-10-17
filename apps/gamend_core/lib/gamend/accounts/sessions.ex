defmodule Gamend.Accounts.Sessions do
  @moduledoc """
  Signing in and staying signed in: session and magic-link tokens, the emails
  that carry them, and listing or revoking a user's sessions.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name. Revoking *every* token on a credential change stays there, next
  to the writes that trigger it.
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache
  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Accounts.UserNotifier
  alias Gamend.Accounts.UserToken
  alias Gamend.Repo

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    Accounts.touch_last_seen(user)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {User.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: User.t() | nil
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email. Opening the link proves they
     own the inbox, so the user gets confirmed, logged in, and all tokens -
     including session ones - are expired.

  3. As 2, with a password set: registered when `POST /api/v1/register` still
     took one, or a guest account given an email, and never confirmed. The
     password is removed as the email is confirmed. Whoever set it did so
     before anyone proved they own the inbox, so it may be someone else's,
     and kept it would sign them into the account its owner has just claimed
     (the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`). The owner sets a new one in settings. The
     confirmation email's link removes it the same way
     (`Gamend.Accounts.confirm_user_by_token/1`); its code sets the password.
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, :not_found | Ecto.Changeset.t() | term()}
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil} = user, _token} ->
        handle_unconfirmed_login(user)

      {user, token} ->
        Repo.delete!(token)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_user_logged_in, [user])
          Gamend.Quests.report_event(user.id, "login")
        end)

        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  # Dropping the password is what makes confirming safe (case 3 above); a
  # user without one is unchanged by it.
  defp handle_unconfirmed_login(user) do
    result =
      user
      |> User.confirm_changeset()
      |> Ecto.Changeset.put_change(:hashed_password, nil)
      |> Accounts.update_user_and_delete_all_tokens()

    case result do
      {:ok, {user, _tokens}} = ok ->
        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_user_logged_in, [user])
          Gamend.Quests.report_event(user.id, "login")
        end)

        ok

      other ->
        other
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(
          User.t(),
          String.t(),
          (String.t() -> String.t())
        ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  @spec deliver_login_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    ids =
      Repo.all(
        from(t in UserToken, where: t.token == ^token and t.context == "session", select: t.id)
      )

    Repo.delete_all(from(t in UserToken, where: t.id in ^ids))
    Enum.each(ids, &Gamend.Cache.invalidate({:accounts, :user_token, &1}))
    :ok
  end

  @doc false
  @spec get_user_token(Ecto.UUID.t()) :: UserToken.t() | nil
  @decorate cacheable(
              key: {:accounts, :user_token, id},
              match: &Accounts.cache_match/1,
              opts: [ttl: 60_000]
            )
  def get_user_token(id) do
    Repo.get_uuid(UserToken, id)
  end

  @doc false
  @spec get_user_token!(Ecto.UUID.t()) :: UserToken.t()
  def get_user_token!(id) do
    case get_user_token(id) do
      %UserToken{} = token -> token
      nil -> raise Ecto.NoResultsError, queryable: UserToken
    end
  end

  @doc false
  @spec delete_user_token(UserToken.t()) ::
          {:ok, UserToken.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_user_token(%UserToken{} = token) do
    # The token may come from the cache, and a sign-out or a revoke deletes
    # tokens with one query that leaves each cached copy behind.
    case Repo.rescue_stale(:not_found, fn -> Repo.delete(token) end) do
      {:error, %Ecto.Changeset{}} = error ->
        error

      result ->
        _ = Gamend.Cache.invalidate({:accounts, :user_token, token.id})
        result
    end
  end

  @doc """
  Lists tokens for a given user, optionally filtered by context.
  """
  @spec list_user_tokens(Ecto.UUID.t(), keyword()) :: [UserToken.t()]
  def list_user_tokens(user_id, opts \\ []) when is_binary(user_id) do
    context = Keyword.get(opts, :context)

    from(t in UserToken, where: t.user_id == ^user_id, order_by: [desc: t.inserted_at])
    |> then(fn q ->
      if context, do: where(q, [t], t.context == ^context), else: q
    end)
    |> Repo.all()
  end

  @doc """
  Counts tokens for a given user.
  """
  @spec count_user_tokens(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_tokens(user_id) when is_binary(user_id) do
    from(t in UserToken, where: t.user_id == ^user_id, select: count())
    |> Repo.one()
  end

  @doc """
  Revokes all session tokens for a user (mass logout).
  """
  @spec revoke_all_user_sessions(Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def revoke_all_user_sessions(user_id) when is_binary(user_id) do
    token_ids =
      from(t in UserToken,
        where: t.user_id == ^user_id and t.context == "session",
        select: t.id
      )
      |> Repo.all()

    result =
      from(t in UserToken, where: t.user_id == ^user_id and t.context == "session")
      |> Repo.delete_all()

    Enum.each(token_ids, fn id ->
      _ = Gamend.Cache.invalidate({:accounts, :user_token, id})
    end)

    result
  end
end
