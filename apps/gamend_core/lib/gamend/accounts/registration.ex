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
  there. The first user becomes the admin and gets no email.
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
    register_and_deliver(attrs, &User.email_changeset/3, confirmation_url_fun, notifier)
  end

  @doc """
  Register a user with an email and a password and queue the confirmation
  email, as `register_user_and_deliver/3` does for the browser form: how a
  game client signs up (`POST /api/v1/register`).
  """
  @spec register_user_with_password_and_deliver(
          Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_user_with_password_and_deliver(
        attrs,
        confirmation_url_fun,
        notifier \\ Gamend.Accounts.UserNotifier
      )
      when is_function(confirmation_url_fun, 1) do
    register_and_deliver(attrs, &User.registration_changeset/3, confirmation_url_fun, notifier)
  end

  defp register_and_deliver(attrs, base_changeset, confirmation_url_fun, notifier) do
    # Normalize keys to strings to match form submissions
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    # Check if this is the first user and make them admin
    is_first_user = first_user?()

    build = fn attrs, opts ->
      %User{}
      |> base_changeset.(attrs, opts)
      |> User.username_changeset(attrs)
      |> maybe_make_first_user_admin(is_first_user)
      |> maybe_deactivate_new_user(is_first_user)
    end

    changeset_fun = &build.(&1, [])

    # The plugins' tentative user needs neither the password hash (Argon2id,
    # ~24ms) nor the email-uniqueness query: the real changeset runs both.
    # Unhashed, the plaintext would stay on it, so it is dropped.
    tentative_fun = fn attrs ->
      attrs
      |> build.(hash_password: false, validate_unique: false)
      |> Ecto.Changeset.delete_change(:password)
    end

    # Two inserts and nothing slow: the confirmation email is a job, queued
    # here so a committed account always has one, and sent after commit.
    transaction_fun = fn changeset ->
      with {:ok, %User{} = user} <- Repo.insert(changeset),
           :ok <- queue_confirmation(user, is_first_user, confirmation_url_fun, notifier) do
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

  defp queue_confirmation(_user, true = _is_first_user, _url_fun, _notifier), do: :ok

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
  Confirm a user by an email confirmation token (context: "confirm").

  Returns {:ok, user} when the token is valid and user was confirmed.
  Returns {:error, :not_found} or {:error, :expired} when token is invalid/expired.
  """
  @spec confirm_user_by_token(String.t()) :: {:ok, User.t()} | {:error, :invalid | :not_found}
  def confirm_user_by_token(token) when is_binary(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         hashed <- :crypto.hash(:sha256, decoded),
         {:ok, %User{} = user} <- fetch_user_for_confirm_token(hashed),
         {:ok, %User{} = confirmed_user} <- confirm_user_by_token_tx(user) do
      {:ok, Accounts.get_user(confirmed_user.id)}
    else
      :error ->
        {:error, :invalid}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp fetch_user_for_confirm_token(hashed) do
    query =
      from t in UserToken,
        where: t.token == ^hashed and t.context == "confirm",
        where: t.inserted_at > ago(^UserToken.confirm_validity_in_days(), "day"),
        join: u in assoc(t, :user),
        select: {u, t}

    case Repo.one(query) do
      {%User{} = user, _token} -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

  defp confirm_user_by_token_tx(%User{} = user) do
    Gamend.AfterCommit.transaction(fn ->
      {:ok, confirmed_user} = confirm_user(user)

      Repo.delete_all(
        from(ut in UserToken, where: ut.user_id == ^confirmed_user.id and ut.context == "confirm")
      )

      confirmed_user
    end)
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
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      UserNotifier.deliver_confirmation_instructions(
        user,
        confirmation_url_fun.(encoded_token)
      )
    end
  end
end
