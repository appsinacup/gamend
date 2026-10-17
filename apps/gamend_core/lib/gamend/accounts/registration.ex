defmodule Gamend.Accounts.Registration do
  @moduledoc """
  Creating an account and confirming it: registration, the generated username,
  the first-user-is-admin rule and account activation, and email confirmation.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Gamend.Accounts.ConfirmationMailer
  alias Gamend.Accounts.LoginLockouts
  alias Gamend.Accounts.User
  alias Gamend.Accounts.UsernameGenerator
  alias Gamend.Accounts.UserNotifier
  alias Gamend.Accounts.UserToken
  alias Gamend.Repo
  alias Gamend.Types

  # Upper bound on cross-node staleness for cached user structs: explicit
  # invalidations propagate immediately via `Gamend.Cache.invalidate/1`,
  # and this TTL caps staleness if an invalidation broadcast is ever missed.
  alias Gamend.Accounts

  @username_insert_attempts 4

  # Asked on every registration, and it only needs "is the table empty" — a
  # count answers a much harder question at O(rows). Measured on SQLite it was
  # 70us at 1k users, 480us at 10k and 2.5ms at 50k, by which point it was 82%
  # of the whole registration; `exists?` stops at the first row and stays flat.
  @doc false
  def first_user? do
    not Repo.exists?(User)
  end

  @doc false
  def maybe_make_first_user_admin(changeset, true) do
    Ecto.Changeset.put_change(changeset, :is_admin, true)
  end

  def maybe_make_first_user_admin(changeset, false), do: changeset

  # The first account is confirmed as it is created: it gets no email to
  # confirm with (there may be no mail server configured yet), and a password
  # does not sign in an unconfirmed account.
  defp maybe_confirm_first_user(changeset, true = _is_first_user) do
    Ecto.Changeset.put_change(changeset, :confirmed_at, DateTime.utc_now(:second))
  end

  defp maybe_confirm_first_user(changeset, false), do: changeset

  # When account activation is required, new non-admin users start deactivated.
  # The first user (admin) is always activated.
  @doc false
  def maybe_deactivate_new_user(changeset, true = _is_first_user), do: changeset

  def maybe_deactivate_new_user(changeset, _is_first_user) do
    if Accounts.require_account_activation?() do
      Ecto.Changeset.put_change(changeset, :is_activated, false)
    else
      changeset
    end
  end

  @doc """
  Registers a user.

  ## Attributes

  See `t:Gamend.Types.user_registration_attrs/0` for available fields.

  ## Examples

      iex> register_user(%{email: "user@example.com", password: "secret123"})
      {:ok, %User{}}

      iex> register_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(Types.user_registration_attrs()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    # Normalize keys to strings to match form submissions
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    # Check if this is the first user and make them admin
    is_first_user = first_user?()

    changeset_fun = fn attrs ->
      %User{}
      |> User.email_changeset(attrs)
      |> User.username_changeset(attrs)
      |> maybe_make_first_user_admin(is_first_user)
      |> maybe_deactivate_new_user(is_first_user)
    end

    with {:ok, attrs} <- run_before_user_register(changeset_fun, attrs),
         {:ok, user} = ok <- insert_user_with_username_retry(changeset_fun, attrs) do
      Accounts.invalidate_users_count_cache()

      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_user_register, [user])
      end)

      ok
    end
  end

  @doc """
  Register a user and queue its confirmation email.

  `confirmation_url_fun` maps an encoded token to the confirmation URL. The
  email goes out from the `mailers` queue (`Gamend.Accounts.ConfirmationMailer`),
  enqueued in the transaction that inserts the user: the call returns once
  both are committed, without waiting on SMTP, and a failed send is retried
  there. The email carries a link and a code (`confirm_user_by_code/3`).

  The first user becomes the admin and is confirmed, with no email: the
  browser form signs it in itself. A caller that cannot uses
  `register_unconfirmed_user_and_deliver/3`.

  No password is taken. Whoever registers an address has not shown they own
  it, so a password chosen now could be someone else's, and it would sign them
  into the account once the address's owner confirmed it. The password is set
  after the inbox is proved: with the code, or in the settings the link opens.
  """
  @spec register_user_and_deliver(Types.user_registration_attrs(), (String.t() -> String.t())) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  @spec register_user_and_deliver(
          Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_user_and_deliver(
        attrs,
        confirmation_url_fun,
        notifier \\ Gamend.Accounts.UserNotifier
      )
      when is_function(confirmation_url_fun, 1) do
    register_and_deliver(attrs, confirmation_url_fun, notifier, true)
  end

  @doc """
  `register_user_and_deliver/3` for a game client (`POST /api/v1/register`):
  every account it makes starts unconfirmed and is sent the email, the first
  one too. A client has no page to sign the first account in, and with no
  password it could not sign in any other way, so it confirms with the code
  like everyone else (`confirm_user_by_code/3`). It still becomes the admin.
  """
  @spec register_unconfirmed_user_and_deliver(
          Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_unconfirmed_user_and_deliver(
        attrs,
        confirmation_url_fun,
        notifier \\ Gamend.Accounts.UserNotifier
      )
      when is_function(confirmation_url_fun, 1) do
    register_and_deliver(attrs, confirmation_url_fun, notifier, false)
  end

  @doc """
  Sign-up for a visitor who is already playing on an anonymous account: the
  email goes on THAT account, and the confirmation email is queued exactly as
  for a new one. Same account id, so everything it holds stays; the link in the
  email signs in to it on any device and confirms the address.

  `{:error, :not_anonymous}` for an account that already has an identity.
  """
  @spec upgrade_anonymous_user_and_deliver(
          User.t(),
          Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def upgrade_anonymous_user_and_deliver(
        %User{} = user,
        attrs,
        confirmation_url_fun,
        notifier \\ Gamend.Accounts.UserNotifier
      )
      when is_function(confirmation_url_fun, 1) do
    if User.anonymous?(user) do
      attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

      Gamend.AfterCommit.transaction(fn ->
        with {:ok, %User{} = updated} <- user |> User.email_changeset(attrs) |> Repo.update(),
             :ok <- queue_confirmation(updated, false, confirmation_url_fun, notifier) do
          updated
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, updated} ->
          Accounts.invalidate_user_cache(updated)
          {:ok, updated}

        other ->
          other
      end
    else
      {:error, :not_anonymous}
    end
  end

  # `confirm_first_user?`: whether the first account is confirmed as it is
  # created and gets no email (the browser form, which signs it in), or goes
  # through the email like any other (a game client).
  defp register_and_deliver(attrs, confirmation_url_fun, notifier, confirm_first_user?) do
    # Normalize keys to strings to match form submissions. Only the email
    # and the username are cast (`User.email_changeset/3`).
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    # Check if this is the first user and make them admin
    is_first_user = first_user?()
    confirmed_first_user = is_first_user and confirm_first_user?

    build = fn attrs, opts ->
      %User{}
      |> User.email_changeset(attrs, opts)
      |> User.username_changeset(attrs)
      |> maybe_make_first_user_admin(is_first_user)
      |> maybe_confirm_first_user(confirmed_first_user)
      |> maybe_deactivate_new_user(is_first_user)
    end

    changeset_fun = &build.(&1, [])

    # The plugins' tentative user does not need the email-uniqueness query:
    # the real changeset runs it.
    tentative_fun = &build.(&1, validate_unique: false)

    # Two inserts and nothing slow: the confirmation email is a job, queued
    # here so a committed account always has one, and sent after commit.
    transaction_fun = fn changeset ->
      with {:ok, %User{} = user} <- Repo.insert(changeset),
           :ok <- queue_confirmation(user, confirmed_first_user, confirmation_url_fun, notifier) do
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end

    with {:ok, attrs} <- run_before_user_register(tentative_fun, attrs),
         {:ok, %User{} = user} <-
           transact_with_username_retry(changeset_fun, transaction_fun, attrs) do
      Accounts.invalidate_users_count_cache()

      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_user_register, [user])
      end)

      {:ok, user}
    end
  end

  defp queue_confirmation(_user, true = _confirmed, _url_fun, _notifier), do: :ok

  defp queue_confirmation(user, false, confirmation_url_fun, notifier) do
    case user |> ConfirmationMailer.new_for(confirmation_url_fun, notifier) |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_generated_username(attrs) do
    case attrs["username"] do
      u when is_binary(u) and u != "" -> attrs
      _ -> Map.put(attrs, "username", UsernameGenerator.generate(attrs))
    end
  end

  # Runs the before_user_register pipeline with the tentative (not yet
  # inserted) user built from attrs. Returns the possibly hook-modified,
  # string-keyed attrs.
  @doc false
  def run_before_user_register(changeset_fun, attrs) do
    attrs = put_generated_username(attrs)
    tentative = attrs |> changeset_fun.() |> Ecto.Changeset.apply_changes()

    case Gamend.Hooks.internal_call(:before_user_register, [tentative, attrs]) do
      {:ok, returned} when is_map(returned) and not is_struct(returned) ->
        {:ok, Map.new(returned, fn {k, v} -> {to_string(k), v} end)}

      {:ok, _other} ->
        {:ok, attrs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Registration must never fail on a bad username: a hook-supplied or
  # generated name that is invalid or already taken is replaced with a
  # freshly generated one (wider suffix on later attempts). Other changeset
  # errors pass through untouched.
  @doc false
  def insert_user_with_username_retry(changeset_fun, attrs, attempt \\ 1) do
    case Repo.insert(changeset_fun.(attrs)) do
      {:ok, _user} = ok ->
        ok

      {:error, %Ecto.Changeset{} = changeset} = err ->
        case regenerate_username_attrs(attrs, changeset, attempt) do
          {:retry, attrs} -> insert_user_with_username_retry(changeset_fun, attrs, attempt + 1)
          :no_retry -> err
        end
    end
  end

  # A unique violation aborts the surrounding Postgres transaction, so the
  # retry must restart the whole transaction rather than re-insert inside
  # the aborted one.
  # The changeset runs the `validate_username` hook, so it is built before the
  # transaction opens: a hook never runs inside one.
  defp transact_with_username_retry(changeset_fun, transaction_fun, attrs, attempt \\ 1) do
    changeset = changeset_fun.(attrs)

    case Gamend.AfterCommit.transaction(fn -> transaction_fun.(changeset) end) do
      {:error, %Ecto.Changeset{} = changeset} = err ->
        case regenerate_username_attrs(attrs, changeset, attempt) do
          {:retry, attrs} ->
            transact_with_username_retry(changeset_fun, transaction_fun, attrs, attempt + 1)

          :no_retry ->
            err
        end

      other ->
        other
    end
  end

  defp regenerate_username_attrs(attrs, %Ecto.Changeset{errors: errors}, attempt) do
    if Keyword.has_key?(errors, :username) and attempt < @username_insert_attempts do
      regenerated = UsernameGenerator.generate(attrs, attempt + 1)

      Logger.warning(
        "username #{inspect(attrs["username"])} rejected " <>
          "(#{inspect(Keyword.get_values(errors, :username))}), retrying as #{regenerated}"
      )

      {:retry, Map.put(attrs, "username", regenerated)}
    else
      :no_retry
    end
  end

  # Registration deliberately does NOT attach a device id.
  #
  # `device_id` is a bearer credential: `find_or_create_from_device/2` is a plain
  # lookup on the column, so whoever knows the value holds the account. Accepting
  # it from registration attrs meant a client — LiveView form payloads are
  # client-controlled — could register the victim's email with a device id of
  # their choosing. When the victim later claimed that row by magic link or by an
  # OAuth provider asserting the same verified email, the planted device id still
  # resolved to it, and survived `token_version` bumps because device login never
  # consults them.
  #
  # A device is attached only while authenticated (`link_device_id/2`, reached
  # through `POST /api/v1/me/device`) or when device login itself creates the
  # account (`do_find_or_create_from_device/2`).

  @doc """
  Confirms a user's email by setting confirmed_at timestamp.

  ## Examples

      iex> confirm_user(user)
      {:ok, %User{}}

  """
  @spec confirm_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def confirm_user(user) do
    case user
         |> User.confirm_changeset()
         |> Repo.update() do
      {:ok, %User{} = updated} = ok ->
        Accounts.invalidate_user_cache(user)
        Accounts.invalidate_user_cache(updated)
        ok

      other ->
        other
    end
  end

  @doc """
  The account an emailed confirmation link belongs to, or `nil` for a link
  that is malformed, spent or expired. It only reads: the page the link opens
  shows the account, and confirming waits for its button
  (`confirm_user_by_token/1`), so a mail scanner that opens every link in an
  email confirms nothing and spends nothing.
  """
  @spec get_user_by_confirm_token(String.t()) :: User.t() | nil
  def get_user_by_confirm_token(token) when is_binary(token) do
    case fetch_user_for_confirm_token(token) do
      {:ok, user} -> user
      {:error, _} -> nil
    end
  end

  @doc """
  Confirm a user by the token in the emailed link (context: "confirm").

  Returns {:ok, user} when the token is valid and user was confirmed.
  Returns {:error, :not_found} or {:error, :invalid} when token is invalid/expired.

  Confirming spends the link and the code sent with it. An account confirmed
  this way has no password: registration takes none, and one set before the
  address was proved is removed, since whoever set it may not own the inbox
  (an account registered when the API still took one, or a guest account
  that was given an email). Its owner sets one in settings, where the link's
  page signs them in, or confirms with the code instead.
  """
  @spec confirm_user_by_token(String.t()) :: {:ok, User.t()} | {:error, :invalid | :not_found}
  def confirm_user_by_token(token) when is_binary(token) do
    with {:ok, %User{} = user} <- fetch_user_for_confirm_token(token),
         {:ok, %User{} = confirmed_user} <- confirm_user_by_token_tx(user) do
      {:ok, Accounts.get_user(confirmed_user.id)}
    end
  end

  defp fetch_user_for_confirm_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        query =
          from t in UserToken,
            where: t.token == ^:crypto.hash(:sha256, decoded) and t.context == "confirm",
            where: t.inserted_at > ago(^UserToken.confirm_validity_in_days(), "day"),
            join: u in assoc(t, :user),
            select: u

        case Repo.one(query) do
          %User{} = user -> {:ok, user}
          nil -> {:error, :not_found}
        end

      :error ->
        {:error, :invalid}
    end
  end

  defp confirm_user_by_token_tx(%User{} = user) do
    changeset =
      if user.confirmed_at,
        do: User.confirm_changeset(user),
        else: user |> User.confirm_changeset() |> Ecto.Changeset.put_change(:hashed_password, nil)

    result =
      Gamend.AfterCommit.transaction(fn ->
        confirmed_user = Repo.update!(changeset)
        Repo.delete_all(confirmation_tokens_query(confirmed_user))
        confirmed_user
      end)

    with {:ok, confirmed_user} <- result do
      Accounts.invalidate_user_cache(user)
      Accounts.invalidate_user_cache(confirmed_user)
      {:ok, confirmed_user}
    end
  end

  # Every link and code still waiting for `user`'s inbox.
  defp confirmation_tokens_query(%User{id: user_id}) do
    from(t in UserToken,
      where: t.user_id == ^user_id and t.context in ["confirm", "confirm_code"]
    )
  end

  @doc """
  Confirms the unconfirmed account registered to `email` with the code from
  its confirmation email, sets its password, and returns it signed in by the
  caller (`POST /api/v1/register/confirm`).

  The code is the proof that the caller reads the inbox, which is why the
  password is set here and never at registration.

  - `{:error, %Ecto.Changeset{}}` for a password the account would refuse.
    It is checked before the code, so it costs no attempt and says nothing
    about the code.
  - `{:error, :invalid_code}` for a wrong, spent or expired code, an address
    with no unconfirmed account, or one already confirmed: the same answer,
    so it tells no one which addresses are registered.
  - `{:error, {:locked, seconds}}`: a wrong code counts toward the address's
    sign-in lockout (`Gamend.Accounts.LoginLockouts`), shared with passwords.
    The failure that locks it also voids the code, so guessing needs a fresh
    email for every few tries; the link keeps working.

  Success revokes every earlier token of the account, as a password change
  does, and returns them so the caller can disconnect the sessions.
  """
  @spec confirm_user_by_code(String.t(), String.t(), String.t()) ::
          {:ok, {User.t(), [UserToken.t()]}}
          | {:error, :invalid_code | {:locked, pos_integer()} | Ecto.Changeset.t()}
  def confirm_user_by_code(email, code, password)
      when is_binary(email) and is_binary(code) and is_binary(password) do
    attrs = %{"password" => password}
    checked = User.password_changeset(%User{}, attrs, hash_password: false)

    with {:password, true} <- {:password, checked.valid?},
         :ok <- LoginLockouts.check(email) do
      # Read off an email, so spaces and a dash between the digit groups pass.
      redeem_code(email, String.replace(code, ~r/[\s-]/u, ""), attrs)
    else
      {:password, false} -> {:error, %{checked | action: :validate}}
      {:locked, seconds} -> {:error, {:locked, seconds}}
    end
  end

  defp redeem_code(email, code, attrs) do
    with %User{confirmed_at: nil} = user <- user_by_email_uncached(email),
         true <- Repo.exists?(UserToken.verify_confirm_code_query(user, code)) do
      LoginLockouts.clear(email)

      # Hashed here, before `update_user_and_delete_all_tokens/1` opens its
      # transaction: the hash is the slow part.
      user
      |> User.password_changeset(attrs)
      |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
      |> Accounts.update_user_and_delete_all_tokens()
    else
      _ -> code_failure(email)
    end
  end

  # Straight from the table, as `ConfirmationMailer` reads: this write sets a
  # password and bumps `token_version` from the struct it is given, which a
  # stale cached copy would get wrong.
  defp user_by_email_uncached(email) do
    case email |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> Repo.get_by(User, email: normalized)
    end
  end

  defp code_failure(email) do
    case LoginLockouts.record_failure(email) do
      :ok ->
        {:error, :invalid_code}

      {:locked, seconds} ->
        with %User{confirmed_at: nil} = user <- user_by_email_uncached(email) do
          Repo.delete_all(where(confirmation_tokens_query(user), context: "confirm_code"))
        end

        {:error, {:locked, seconds}}
    end
  end

  @doc """
  Sends the confirmation email again, with a new code, to the unconfirmed
  account registered to `email` (`POST /api/v1/register/resend`). Only the
  newest code works; links already sent keep working until they expire.

  Always `:ok`, whether or not such an account exists, so it tells no one
  which addresses are registered. At most one email per account per minute
  is queued; the rest are dropped.
  """
  @spec resend_confirmation(String.t(), (String.t() -> String.t()), module()) :: :ok
  def resend_confirmation(email, confirmation_url_fun, notifier \\ Gamend.Accounts.UserNotifier)
      when is_binary(email) and is_function(confirmation_url_fun, 1) do
    with %User{confirmed_at: nil, email: address} = user when is_binary(address) <-
           Accounts.get_user_by_email(email) do
      user
      |> ConfirmationMailer.new_for(confirmation_url_fun, notifier,
        unique: [period: 60, keys: [:user_id]]
      )
      |> Oban.insert!()
    end

    :ok
  end

  @doc false
  # Mints one email's link and code for `user`, replacing any earlier code.
  # Returns `{encoded_link_token, code}`.
  def insert_confirmation_tokens(%User{} = user) do
    {encoded, link_token} = UserToken.build_email_token(user, "confirm")
    {code, code_token} = UserToken.build_confirm_code_token(user)

    {:ok, _} =
      Gamend.AfterCommit.transaction(fn ->
        Repo.delete_all(where(confirmation_tokens_query(user), context: "confirm_code"))
        Repo.insert!(link_token)
        Repo.insert!(code_token)
      end)

    {encoded, code}
  end

  @spec change_user_registration(User.t()) :: Ecto.Changeset.t()
  @spec change_user_registration(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, [])
  end

  @doc """
  A registration changeset for live form feedback, with the uniqueness query
  skipped.

  `change_user_registration/2` runs `unsafe_validate_unique`, which is right on
  submit and wrong on every keystroke: the registration form's `validate` event
  is neither rate-limited nor captcha'd, so running it there turned the form
  into an unauthenticated oracle for "does this address have an account here?",
  one query per character typed. Submitting still checks, and the unique index
  is what actually enforces it.

  Separate function rather than an option, because `mix gen.sdk` cannot generate
  a stub for a function carrying two default arguments.
  """
  @spec change_user_registration_for_validation(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_registration_for_validation(%User{} = user, attrs) do
    User.registration_changeset(user, attrs, validate_unique: false)
  end

  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, :already_confirmed | term()}
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, code} = insert_confirmation_tokens(user)

      UserNotifier.deliver_confirmation_instructions(
        user,
        confirmation_url_fun.(encoded_token),
        code
      )
    end
  end
end
