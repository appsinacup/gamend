defmodule Gamend.Accounts do
  @moduledoc ~S"""
  The Accounts context.

  ## Usage

      # Lookup by id or email
      user = Gamend.Accounts.get_user(123)
      user = Gamend.Accounts.get_user_by_email("me@example.com")

      # Update a user
      {:ok, user} = Gamend.Accounts.update_user(user, %{display_name: "NewName"})

      # Search (paginated) and count
      users = Gamend.Accounts.search_users("bob", page: 1, page_size: 25)
      count = Gamend.Accounts.count_search_users("bob")



  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Attach a device_id to an existing user record. Returns {:ok, user} or
    {:error, changeset} if the device_id is already used.
    
  """
  @spec attach_device_to_user(Gamend.Accounts.User.t(), String.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def attach_device_to_user(_user, _device_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.attach_device_to_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Checks an email and password, counting failures per address
    (`Gamend.Accounts.LoginLockouts`).
    
    `{:error, {:locked, seconds}}` when the address is locked, before the
    password is looked at, and for the failure that locks it.
    
  """
  @spec authenticate_by_password(String.t(), String.t()) ::
          {:ok, Gamend.Accounts.User.t()}
          | {:error, :invalid_credentials | {:locked, pos_integer()}}
  def authenticate_by_password(_email, _password) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.authenticate_by_password/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Broadcast a `friend_updated` event to all accepted friends.
    
    Used when public user data changes: map presence, display name, avatar,
    player metadata, ship metadata, lobby/party state, etc.
    
  """
  @spec broadcast_friend_update(Gamend.Accounts.User.t()) :: :ok
  def broadcast_friend_update(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.broadcast_friend_update/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Broadcast a `member_updated` event to the user's current lobby and
    party channels so other members see the profile change (display name, avatar,
    metadata, etc.) in real-time.
    
    This is fire-and-forget and safe to call even when the user is not in a lobby
    or party.
    
  """
  @spec broadcast_member_update(Gamend.Accounts.User.t()) :: :ok
  def broadcast_member_update(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.broadcast_member_update/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Broadcast that the given user has been updated.
    
    This helper is intentionally small and only broadcasts a compact payload
    intended for client consumption through the `user:<id>` topic.
    
  """
  @spec broadcast_user_update(Gamend.Accounts.User.t()) :: :ok
  def broadcast_user_update(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.broadcast_user_update/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Stores `user` under the canonical user cache key (with the standard TTL).
    
    Call after writes that update the user row outside this module (e.g. lobby
    or party membership) so subsequent `get_user/1` reads stay warm and
    consistent instead of serving the pre-write struct until the TTL expires.
    
  """
  @spec cache_user(Gamend.Accounts.User.t()) :: Gamend.Accounts.User.t()
  def cache_user(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.cache_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user` may upload an avatar, per `anonymous_can_upload_avatar`.
    
  """
  @spec can_upload_avatar?(Gamend.Accounts.User.t()) :: boolean()
  def can_upload_avatar?(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.can_upload_avatar?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Keep an account that was scheduled for deletion. A no-op for one that was not.
    
  """
  @spec cancel_deletion(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def cancel_deletion(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.cancel_deletion/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user display_name.
    
  """
  @spec change_user_display_name(Gamend.Accounts.User.t()) :: Ecto.Changeset.t()
  def change_user_display_name(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_display_name/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user display_name.
    
  """
  @spec change_user_display_name(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
  def change_user_display_name(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_display_name/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user email.
    
    See `Gamend.Accounts.User.email_changeset/3` for a list of supported options.
    
    ## Examples
    
        iex> change_user_email(user)
        %Ecto.Changeset{data: %User{}}
    
    
  """
  @spec change_user_email(Gamend.Accounts.User.t()) :: Ecto.Changeset.t()
  def change_user_email(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_email/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user email.
    
    See `Gamend.Accounts.User.email_changeset/3` for a list of supported options.
    
    ## Examples
    
        iex> change_user_email(user)
        %Ecto.Changeset{data: %User{}}
    
    
  """
  @spec change_user_email(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
  def change_user_email(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_email/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user email.
    
    See `Gamend.Accounts.User.email_changeset/3` for a list of supported options.
    
    ## Examples
    
        iex> change_user_email(user)
        %Ecto.Changeset{data: %User{}}
    
    
  """
  @spec change_user_email(Gamend.Accounts.User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_email(_user, _attrs, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_email/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user password.
    
    See `Gamend.Accounts.User.password_changeset/3` for a list of supported options.
    
    ## Examples
    
        iex> change_user_password(user)
        %Ecto.Changeset{data: %User{}}
    
    
  """
  @spec change_user_password(Gamend.Accounts.User.t()) :: Ecto.Changeset.t()
  def change_user_password(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_password/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user password.
    
    See `Gamend.Accounts.User.password_changeset/3` for a list of supported options.
    
    ## Examples
    
        iex> change_user_password(user)
        %Ecto.Changeset{data: %User{}}
    
    
  """
  @spec change_user_password(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
  def change_user_password(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_password/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns an `%Ecto.Changeset{}` for changing the user password.
    
    See `Gamend.Accounts.User.password_changeset/3` for a list of supported options.
    
    ## Examples
    
        iex> change_user_password(user)
        %Ecto.Changeset{data: %User{}}
    
    
  """
  @spec change_user_password(Gamend.Accounts.User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_password(_user, _attrs, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_password/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec change_user_registration(Gamend.Accounts.User.t()) :: Ecto.Changeset.t()
  def change_user_registration(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_registration/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec change_user_registration(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
  def change_user_registration(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_registration/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec change_user_registration_for_validation(Gamend.Accounts.User.t(), map()) ::
          Ecto.Changeset.t()
  def change_user_registration_for_validation(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_user_registration_for_validation/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec change_username(Gamend.Accounts.User.t()) :: Ecto.Changeset.t()
  def change_username(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_username/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec change_username(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
  def change_username(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.change_username/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Confirms a user's email by setting confirmed_at timestamp.
    
    ## Examples
    
        iex> confirm_user(user)
        {:ok, %User{}}
    
    
  """
  @spec confirm_user(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def confirm_user(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.confirm_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Confirm a user by an email confirmation token (context: "confirm").
    
    Returns {:ok, user} when the token is valid and user was confirmed.
    Returns {:error, :not_found} or {:error, :expired} when token is invalid/expired.
    
  """
  @spec confirm_user_by_token(String.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :invalid | :not_found}
  def confirm_user_by_token(_token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.confirm_user_by_token/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many accounts hold the admin flag.
    
    Used to refuse the write that would take that number to zero: nothing else can
    grant `is_admin`, so an installation that reaches zero admins cannot be
    administered again.
    
  """
  @spec count_admins() :: non_neg_integer()
  def count_admins() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_admins/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Row count for `list_all_users/2` under the same filters.
  """
  @spec count_list_all_users(map()) :: non_neg_integer()
  def count_list_all_users(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_list_all_users/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users matching a username/display name query or exact id. Returns integer.
    
  """
  @spec count_search_users(String.t()) :: non_neg_integer()
  def count_search_users(_query) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_search_users/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users who are not yet activated (is_activated == false).
    
  """
  @spec count_unactivated_users() :: non_neg_integer()
  def count_unactivated_users() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_unactivated_users/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts tokens for a given user.
    
  """
  @spec count_user_tokens(Ecto.UUID.t()) :: non_neg_integer()
  def count_user_tokens(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_user_tokens/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the total number of users.
    
  """
  @spec count_users() :: non_neg_integer()
  def count_users() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_users/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users currently seated in a lobby (`users.lobby_id`, indexed).
  """
  @spec count_users_in_lobbies() :: non_neg_integer()
  def count_users_in_lobbies() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_users_in_lobbies/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users currently in a party (`users.party_id`, indexed).
  """
  @spec count_users_in_parties() :: non_neg_integer()
  def count_users_in_parties() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_users_in_parties/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users currently marked as online.
    
  """
  @spec count_users_online() :: non_neg_integer()
  def count_users_online() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_users_online/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users with a password set (hashed_password not nil/empty).
    
  """
  @spec count_users_with_password() :: non_neg_integer()
  def count_users_with_password() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_users_with_password/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count users with non-empty provider id for a given provider field (e.g. :google_id)
    
  """
  @spec count_users_with_provider(atom()) :: non_neg_integer()
  def count_users_with_provider(_provider_field) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.count_users_with_provider/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes a user and associated resources.
    
    Returns `{:ok, user}` on success or `{:error, changeset}` on failure.
    
  """
  @spec delete_user(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.delete_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes the signed token with the given context.
    
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(_token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.delete_user_session_token/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Removes every stored object belonging to `user_id`.
    
    Best-effort, like `prune_user_avatars/2`: a storage backend that is down must
    not block an account deletion that has already happened at the database level.
    
  """
  @spec delete_user_storage(Ecto.UUID.t()) :: :ok
  def delete_user_storage(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.delete_user_storage/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Days a player's own deletion waits (`auth.deletion_grace_days`); 0 deletes at once.
  """
  @spec deletion_grace_days() :: non_neg_integer()
  def deletion_grace_days() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.deletion_grace_days/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user` is waiting out a deletion grace period.
  """
  @spec deletion_scheduled?(Gamend.Accounts.User.t() | nil) :: boolean()
  def deletion_scheduled?(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.deletion_scheduled?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delivers the magic link login instructions to the given user.
    
  """
  @spec deliver_login_instructions(Gamend.Accounts.User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_login_instructions(_user, _magic_link_url_fun) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Accounts.deliver_login_instructions/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec deliver_user_confirmation_instructions(Gamend.Accounts.User.t(), (String.t() ->
                                                                            String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, :already_confirmed | term()}
  def deliver_user_confirmation_instructions(_user, _confirmation_url_fun) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Accounts.deliver_user_confirmation_instructions/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delivers the update email instructions to the given user.
    
    ## Examples
    
        iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
        {:ok, %{to: ..., body: ...}}
    
    
  """
  @spec deliver_user_update_email_instructions(
          Gamend.Accounts.User.t(),
          String.t(),
          (String.t() -> String.t())
        ) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(_user, _current_email, _update_email_url_fun) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Accounts.deliver_user_update_email_instructions/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether device-based auth is enabled. Defaults to on.
  """
  @spec device_auth_enabled?() :: boolean()
  def device_auth_enabled?() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.device_auth_enabled?/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How to name a user in text a PLAYER reads: `"Ana (drift-2378)"`, or just the
    username when there is no display name. Mirrors the client's
    `UserDisplayUtil.name_with_username`, so a notification and the friends list
    it sends you to name the same person the same way.
    
    Never falls back to the id. Every account has a server-assigned username, and
    `"User #0198f7be-…"` reads like a name while telling the reader nothing.
    
  """
  @spec display_label(Gamend.Accounts.User.t() | Ecto.UUID.t() | nil) :: String.t()
  def display_label(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Accounts.display_label/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The short form of `display_label/1`: the display name, or the username when
    there is none. No parenthesised handle.
    
    Use this where the name sits inside a sentence the player reads — "Ana
    invited you" — and `display_label/1` where it stands on its own and the
    handle disambiguates, such as an admin table or a friends list.
    
    This exists because the fallback was being written inline, differently, in
    four places: parties sent `display_name || ""`, so an invite from a player
    who had set no display name arrived from nobody; group invites wrote
    `display_name || username`; three admin views fell through to the email and
    then the raw id, which `display_label/1` documents as the thing not to do.
    
  """
  @spec display_name(Gamend.Accounts.User.t() | Ecto.UUID.t() | nil) :: String.t()
  def display_name(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        ""

      _ ->
        raise "Gamend.Accounts.display_name/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Accounts whose deletion date has passed. For `Gamend.Retention`.
  """
  @spec due_deletions_query() :: Ecto.Query.t()
  def due_deletions_query() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.due_deletions_query/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds a user by Apple ID or creates a new user from OAuth data.
    
    ## Examples
    
        iex> find_or_create_from_apple(%{apple_id: "123", email: "user@example.com"})
        {:ok, %User{}}
    
    
  """
  @spec find_or_create_from_apple(map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_apple(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_apple/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds or creates a user associated with the given device_id.
    
    If a user already exists with the device_id we return it. Otherwise we
    create an anonymous confirmed user and attach the device_id.
    
  """
  @spec find_or_create_from_device(String.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :disabled | Ecto.Changeset.t() | term()}
  def find_or_create_from_device(_device_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_device/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds or creates a user associated with the given device_id.
    
    If a user already exists with the device_id we return it. Otherwise we
    create an anonymous confirmed user and attach the device_id.
    
  """
  @spec find_or_create_from_device(String.t(), map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :disabled | Ecto.Changeset.t() | term()}
  def find_or_create_from_device(_device_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_device/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds a user by Discord ID or creates a new user from OAuth data.
    
    ## Examples
    
        iex> find_or_create_from_discord(%{discord_id: "123", email: "user@example.com"})
        {:ok, %User{}}
    
    
  """
  @spec find_or_create_from_discord(map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_discord(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_discord/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds a user by Facebook ID or creates a new user from OAuth data.
    
    ## Examples
    
        iex> find_or_create_from_facebook(%{facebook_id: "123", email: "user@example.com"})
        {:ok, %User{}}
    
    
  """
  @spec find_or_create_from_facebook(map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_facebook(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_facebook/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds a user by GitHub ID or creates a new user from OAuth data.
    
    ## Examples
    
        iex> find_or_create_from_github(%{github_id: "123", email: "user@example.com"})
        {:ok, %User{}}
    
    
  """
  @spec find_or_create_from_github(map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_github(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_github/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds a user by Google ID or creates a new user from OAuth data.
    
    ## Examples
    
        iex> find_or_create_from_google(%{google_id: "123", email: "user@example.com"})
        {:ok, %User{}}
    
    
  """
  @spec find_or_create_from_google(map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_google(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_google/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Finds a user by Steam ID or creates a new user from Steam OpenID data.
    
    ## Examples
    
        iex> find_or_create_from_steam(%{steam_id: "12345", email: "user@example.com"})
        {:ok, %User{}}
    
    
  """
  @spec find_or_create_from_steam(map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_steam(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.find_or_create_from_steam/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Generates a session token.
    
  """
  @spec generate_user_session_token(Gamend.Accounts.User.t()) :: binary()
  def generate_user_session_token(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.generate_user_session_token/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns a map of linked OAuth providers for the user.
    
    Each provider is a boolean indicating whether that provider is linked.
    
  """
  @spec get_linked_providers(Gamend.Accounts.User.t()) :: %{
          google: boolean(),
          facebook: boolean(),
          github: boolean(),
          discord: boolean(),
          apple: boolean(),
          steam: boolean(),
          device: boolean()
        }
  def get_linked_providers(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.get_linked_providers/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a single user by ID.
    
    Returns `nil` if the User does not exist.
    
    ## Examples
    
        iex> get_user(123)
        %User{}
    
        iex> get_user(Ecto.UUID.generate())
        nil
    
    
  """
  @spec get_user(Ecto.UUID.t()) :: Gamend.Accounts.User.t() | nil
  def get_user(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a single user.
    
    Raises `Ecto.NoResultsError` if the User does not exist.
    
    ## Examples
    
        iex> get_user!(123)
        %User{}
    
        iex> get_user!(456)
        ** (Ecto.NoResultsError)
    
    
  """
  @spec get_user!(Ecto.UUID.t()) :: Gamend.Accounts.User.t()
  def get_user!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.get_user!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user by their Apple ID.
    
    Returns `%User{}` or `nil`.
    
  """
  @spec get_user_by_apple_id(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_apple_id(_apple_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_apple_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user by their Discord ID.
    
    Returns `%User{}` or `nil`.
    
  """
  @spec get_user_by_discord_id(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_discord_id(_discord_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_discord_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a user by email.
    
    ## Examples
    
        iex> get_user_by_email("foo@example.com")
        %User{}
    
        iex> get_user_by_email("unknown@example.com")
        nil
    
    
  """
  @spec get_user_by_email(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_email(_email) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_email/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a user by email and password. `nil` for a wrong password, and for an
    address locked by too many failures (`authenticate_by_password/2` says which).
    
    ## Examples
    
        iex> get_user_by_email_and_password("foo@example.com", "correct_password")
        %User{}
    
        iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
        nil
    
    
  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_email_and_password(_email, _password) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_email_and_password/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user by their Facebook ID.
    
    Returns `%User{}` or `nil`.
    
  """
  @spec get_user_by_facebook_id(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_facebook_id(_facebook_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_facebook_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user by their GitHub ID.
    
    Returns `%User{}` or `nil`.
    
  """
  @spec get_user_by_github_id(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_github_id(_github_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_github_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user by their Google ID.
    
    Returns `%User{}` or `nil`.
    
  """
  @spec get_user_by_google_id(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_google_id(_google_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_google_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets the user with the given magic link token.
    
  """
  @spec get_user_by_magic_link_token(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_magic_link_token(_token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_magic_link_token/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets the user with the given signed token.
    
    If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
    
  """
  @spec get_user_by_session_token(binary()) :: {Gamend.Accounts.User.t(), DateTime.t()} | nil
  def get_user_by_session_token(_token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_session_token/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a user by their Steam ID (steam_id).
    
    Returns `%User{}` or `nil`.
    
  """
  @spec get_user_by_steam_id(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_steam_id(_steam_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_steam_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a user by their unique username handle (case-insensitive; usernames
    are stored lowercase).
    
  """
  @spec get_user_by_username(String.t()) :: Gamend.Accounts.User.t() | nil
  def get_user_by_username(_username) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Accounts.User{
            id: 0,
            email: "",
            display_name: nil,
            metadata: %{},
            is_admin: false,
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Accounts.get_user_by_username/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns whether the user has a password set.
    
  """
  @spec has_password?(Gamend.Accounts.User.t()) :: boolean()
  def has_password?(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.has_password?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Public cache invalidation for cross-module use (lobbies, parties, groups).
    Accepts a user ID and clears both the primary and all index caches.
    
  """
  @spec invalidate_user_cache_by_id(Ecto.UUID.t()) :: :ok
  def invalidate_user_cache_by_id(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.invalidate_user_cache_by_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Link an OAuth provider to an existing user account. Updates the user
    via the provider's oauth changeset while being careful not to overwrite
    existing email or avatars.
    
    Example: link_account(user, %{discord_id: "123", profile_url: "https://..."}, :discord_id, &User.discord_oauth_changeset/2)
    
  """
  @spec link_account(Gamend.Accounts.User.t(), map(), atom(), (Gamend.Accounts.User.t(), map() ->
                                                                 Ecto.Changeset.t())) ::
          {:ok, Gamend.Accounts.User.t()}
          | {:error, Ecto.Changeset.t() | {:conflict, Gamend.Accounts.User.t()}}
  def link_account(_user, _attrs, _provider_id_field, _changeset_fn) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.link_account/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Link a device_id to an existing user account. This allows the user to
    authenticate using the device_id in addition to their OAuth providers.
    
    Returns {:ok, user} on success or {:error, changeset} if the device_id
    is already used by another account.
    
  """
  @spec link_device_id(Gamend.Accounts.User.t(), String.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def link_device_id(_user, _device_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.link_device_id/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Ids of every admin user.
    
    Used to fan a moderation alert out to whoever can act on it. Not cached: the
    callers are rare (a chat report arriving), and a stale list would silently
    skip a newly promoted moderator.
    
  """
  @spec list_admin_ids() :: [Ecto.UUID.t()]
  def list_admin_ids() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Accounts.list_admin_ids/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Admin user listing: search across identity fields (or an exact id), optional
    facet filters, sorting and pagination — the query behind the admin Users page.
    
    Distinct from `search_users/2`, the privacy-safe player search: this matches
    sensitive fields a player cannot, so it is admin-only.
    
    `filters` keys (string or atom): `:search` (term or full id), `:facets` (list
    of `"online"`, `"unactivated"`, `"unverified"` — an email never confirmed —
    and provider names). `opts`: `:page`,
    `:page_size`, `:sort_field`, `:sort_dir`.
    
  """
  @spec list_all_users(
          map(),
          keyword()
        ) :: [Gamend.Accounts.User.t()]
  def list_all_users(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Accounts.list_all_users/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists tokens for a given user, optionally filtered by context.
    
  """
  @spec list_user_tokens(
          Ecto.UUID.t(),
          keyword()
        ) :: [Gamend.Accounts.UserToken.t()]
  def list_user_tokens(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Accounts.list_user_tokens/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Logs the user in by magic link.
    
    There are three cases to consider:
    
    1. The user has already confirmed their email. They are logged in
       and the magic link is expired.
    
    2. The user has not confirmed their email and no password is set.
       In this case, the user gets confirmed, logged in, and all tokens -
       including session ones - are expired. In theory, no other tokens
       exist but we delete all of them for best security practices.
    
    3. The user has not confirmed their email but a password is set.
       This cannot happen in the default implementation but may be the
       source of security pitfalls. See the "Mixing magic link and password registration" section of
       `mix help phx.gen.auth`.
    
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
          | {:error, :not_found | Ecto.Changeset.t() | term()}
  def login_user_by_magic_link(_token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.login_user_by_magic_link/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Merges `patch` into the user's metadata, leaving untouched every key it does
    not mention.
    
    The counterpart to `Gamend.Lobbies.merge_metadata/2`, and for the same
    reason: `metadata` is one shared map, so a writer that replaces it wipes keys
    belonging to code it has never heard of. Top-level merge, serialized so two
    concurrent merges cannot lose each other.
    
  """
  @spec merge_metadata(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def merge_metadata(_user, _patch) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.merge_metadata/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Aggregate player counts for the public stats endpoint.
    
    Every field is derived, never a counter: a counter would put a write on the
    login path (SQLite has one writer) and would drift from the bulk updates in
    `touch_users/1` and `StalePresenceSweeper`. `players_online` rides the
    partial index over online rows, so it scans the smallest set; the unfiltered
    `players_total` cannot use an index at all, which is what the cache is for.
    
  """
  @spec player_stats() :: %{
          players_online: non_neg_integer(),
          players_total: non_neg_integer(),
          players_offline: non_neg_integer(),
          players_in_lobbies: non_neg_integer(),
          players_in_parties: non_neg_integer()
        }
  def player_stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.player_stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete a user's stored avatar objects except `keep_key`.
    
    Each new avatar gets a fresh random key (`avatars/<user_id>/<rand><ext>`), so
    without this the previous upload or mirror copy lingers in storage forever.
    Best-effort: a failed cleanup leaves the old object rather than failing the
    update that already succeeded.
    
  """
  @spec prune_user_avatars(Ecto.UUID.t(), String.t()) :: :ok
  def prune_user_avatars(_user_id, _keep_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.prune_user_avatars/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Re-derive `account_class` for a user whose stored answer has not changed.
    
    An account graduates on the first of its birth month, and nothing writes to it
    on that day — the derivation is a function of the calendar, not of an event.
    Call this to bring the denormalised column back in step, from a scheduled
    sweep or on login.
    
  """
  @spec refresh_account_class(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def refresh_account_class(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.refresh_account_class/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Registers a user.
    
    ## Attributes
    
    See `t:Gamend.Types.user_registration_attrs/0` for available fields.
    
    ## Examples
    
        iex> register_user(%{email: "user@example.com", password: "secret123"})
        {:ok, %User{}}
    
        iex> register_user(%{email: "invalid"})
        {:error, %Ecto.Changeset{}}
    
    
  """
  @spec register_user(Gamend.Types.user_registration_attrs()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.register_user/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Register a user and queue its confirmation email.
    
    `confirmation_url_fun` maps an encoded token to the confirmation URL. The
    email goes out from the `mailers` queue (`Gamend.Accounts.ConfirmationMailer`),
    enqueued in the transaction that inserts the user: the call returns once
    both are committed, without waiting on SMTP, and a failed send is retried
    there. The first user becomes the admin and gets no email.
    
  """
  @spec register_user_and_deliver(Gamend.Types.user_registration_attrs(), (String.t() ->
                                                                             String.t())) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_user_and_deliver(_attrs, _confirmation_url_fun) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.register_user_and_deliver/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Register a user and queue its confirmation email.
    
    `confirmation_url_fun` maps an encoded token to the confirmation URL. The
    email goes out from the `mailers` queue (`Gamend.Accounts.ConfirmationMailer`),
    enqueued in the transaction that inserts the user: the call returns once
    both are committed, without waiting on SMTP, and a failed send is retried
    there. The first user becomes the admin and gets no email.
    
  """
  @spec register_user_and_deliver(
          Gamend.Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_user_and_deliver(_attrs, _confirmation_url_fun, _notifier) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.register_user_and_deliver/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Register a user with an email and a password and queue the confirmation
    email, as `register_user_and_deliver/3` does for the browser form: how a
    game client signs up (`POST /api/v1/register`).
    
  """
  @spec register_user_with_password_and_deliver(
          Gamend.Types.user_registration_attrs(),
          (String.t() -> String.t()),
          module()
        ) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def register_user_with_password_and_deliver(
        _attrs,
        _confirmation_url_fun,
        _notifier \\ Gamend.Accounts.UserNotifier
      ) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.register_user_with_password_and_deliver/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A player deleting their own account.
    
    With `auth.deletion_grace_days` at 0 the account is deleted now, by
    `delete_user/1`. Otherwise it is scheduled that many days out and signed out
    everywhere (every session, access, refresh and personal API token), and
    `Gamend.Retention` deletes it on the day unless its owner signs in on the
    website first (`cancel_deletion/1`). An account already scheduled keeps its
    date. The expired session tokens come back so the caller can disconnect
    their LiveViews.
    
    Admin deletions and the retention sweeps call `delete_user/1` and never wait.
    
  """
  @spec request_deletion(Gamend.Accounts.User.t()) ::
          {:ok, :deleted}
          | {:ok, {:scheduled, Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
          | {:error, Ecto.Changeset.t()}
  def request_deletion(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.request_deletion/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether new accounts require manual admin activation before they can log in.
    
  """
  @spec require_account_activation?() :: boolean()
  def require_account_activation?() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.require_account_activation?/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Revokes every credential the user holds: all session tokens are deleted and
    `token_version` is bumped, which invalidates all previously issued JWT
    access and refresh tokens ("log out everywhere").
    
    Returns `{:ok, {user, expired_tokens}}`.
    
  """
  @spec revoke_all_tokens(Gamend.Accounts.User.t()) ::
          {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
          | {:error, Ecto.Changeset.t()}
  def revoke_all_tokens(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Accounts.revoke_all_tokens/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Revokes all session tokens for a user (mass logout).
    
  """
  @spec revoke_all_user_sessions(Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def revoke_all_user_sessions(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.revoke_all_user_sessions/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Search users by display name (case-insensitive prefix match) or exact numeric id.
    
    Returns a list of User structs.
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec search_users(String.t()) :: [Gamend.Accounts.User.t()]
  def search_users(_query) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Accounts.search_users/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Search users by display name (case-insensitive prefix match) or exact numeric id.
    
    Returns a list of User structs.
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options.
    
  """
  @spec search_users(String.t(), Gamend.Types.pagination_opts()) :: [Gamend.Accounts.User.t()]
  def search_users(_query, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Accounts.search_users/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Serialize a user into the compact payload used by realtime updates.
    
  """
  @spec serialize_user_payload(Gamend.Accounts.User.t()) :: map()
  def serialize_user_payload(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Accounts.serialize_user_payload/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Record a user's age answer and re-derive what it permits.
    
    Three things happen together, and they have to: the answer is stored, the
    denormalised `account_class` is recomputed from it, and `grandfathered_at` is
    cleared. That last one is the point — an account that predated the age gate
    stops being treated as an adult-by-default the moment it tells us what it
    actually is, in whichever direction that goes.
    
    Refuses with `{:error, :age_change_not_allowed}` when the answer would raise
    the user's age without a stronger signal than the one already recorded. See
    `AgePolicy.may_change_age?/4`: lowering is always allowed, because it only
    ever increases protection.
    
    `attrs` must carry `birth_year`, `birth_month` and `age_method`, and should
    carry `age_country` — without it the highest digital-consent age in the table
    applies, which is the safe reading but not always the right one.
    
  """
  @spec set_user_age(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def set_user_age(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.set_user_age/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Mark a user as offline and update last_seen_at.
    
    Writes only on a real online→offline transition (see `set_user_online/1`).
    
    Returns {:ok, user} on success.
    
  """
  @spec set_user_offline(Ecto.UUID.t()) :: {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def set_user_offline(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.set_user_offline/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Mark a user as online and update last_seen_at.
    
    Writes only on a real offline→online transition: reconnects and extra
    tabs/sockets while already online are no-ops, so reconnect storms don't
    hammer the `users` table (and the `after_user_online` hook fires once per
    session, not once per socket).
    
    Returns {:ok, user} on success.
    
  """
  @spec set_user_online(Ecto.UUID.t()) :: {:ok, Gamend.Accounts.User.t()} | {:error, term()}
  def set_user_online(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.set_user_online/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Checks whether the user is in sudo mode.
    
    With one argument, the window is the one a sudo form is submitted in:
    `sudo_mode_minutes/0` plus ten minutes to fill the form in. The limit can be
    given as second argument in minutes (negative, as an offset from now).
    
  """
  @spec sudo_mode?(Gamend.Accounts.User.t()) :: boolean()
  def sudo_mode?(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.sudo_mode?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec sudo_mode?(Gamend.Accounts.User.t(), integer()) :: boolean()
  def sudo_mode?(_user, _minutes) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.sudo_mode?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How recently a user must have signed in to open a sudo page (`auth.sudo_mode_minutes`).
  """
  @spec sudo_mode_minutes() :: pos_integer()
  def sudo_mode_minutes() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Accounts.sudo_mode_minutes/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates `last_seen_at` to now for the given user. Fire-and-forget — errors are ignored.
    Call on login (session or JWT) to track activity. Also records the UTC day
    for `Gamend.Analytics` (DAU / retention).
    
  """
  @spec touch_last_seen(Gamend.Accounts.User.t()) :: :ok
  def touch_last_seen(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.touch_last_seen/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lightweight version of `touch_last_seen/1` that accepts a user ID directly.
    Performs a single UPDATE without loading the full struct first, setting
    `last_seen_at` to now and `is_online` to true, then invalidates the cache.
    Fire-and-forget — errors are ignored.
    
  """
  @spec touch_last_seen_by_id(Ecto.UUID.t()) :: :ok
  def touch_last_seen_by_id(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Accounts.touch_last_seen_by_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unlink the device_id from a user's account.
    
    Returns {:ok, user} when successful or {:error, reason}.
    
    Guard: we only allow unlinking when the user will still have at least
    one authentication method remaining (OAuth provider or password).
    This prevents users losing all login methods unexpectedly.
    
  """
  @spec unlink_device_id(Gamend.Accounts.User.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :last_auth_method | Ecto.Changeset.t()}
  def unlink_device_id(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.unlink_device_id/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unlink an OAuth provider from a user's account.
    
    provider should be one of :discord, :apple, :google, :facebook, :github, :steam.
    This will return {:ok, user} when successful or {:error, reason}.
    
    Guard: we only allow unlinking when the user will still have at least
    one other social provider remaining. This prevents users losing all
    social logins unexpectedly.
    
  """
  @spec unlink_provider(
          Gamend.Accounts.User.t(),
          :discord | :apple | :google | :facebook | :github | :steam
        ) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :last_provider | Ecto.Changeset.t() | term()}
  def unlink_provider(_user, _provider) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.unlink_provider/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates a user with the given attributes.
    
    This function applies the `User.admin_changeset/2` then updates the user and
    broadcasts the update on success. It returns the same tuple shape as
    `Repo.update/1` so callers can pattern-match as before.
    
    ## Attributes
    
    See `t:Gamend.Types.user_update_attrs/0` for available fields.
    
    ## Examples
    
        iex> update_user(user, %{display_name: "NewName"})
        {:ok, %User{}}
    
        iex> update_user(user, %{metadata: %{level: 5}})
        {:ok, %User{}}
    
    
  """
  @spec update_user(Gamend.Accounts.User.t(), Gamend.Types.user_update_attrs()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.update_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Set the user's avatar URL (`profile_url`), typically after an upload confirmed
    by `Gamend.Storage`. Same cache/broadcast/hook path as other profile edits.
    
  """
  @spec update_user_avatar(Gamend.Accounts.User.t(), String.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_avatar(_user, _url) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.update_user_avatar/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates the user's display name and broadcasts the change.
    
  """
  @spec update_user_display_name(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_display_name(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.update_user_display_name/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates the user email using the given token.
    
    If the token matches, the user email is updated and the token is deleted.
    
  """
  @spec update_user_email(Gamend.Accounts.User.t(), String.t()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, :transaction_aborted}
  def update_user_email(_user, _token) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.update_user_email/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates the user password.
    
    Returns a tuple with the updated user, as well as a list of expired tokens.
    
    ## Examples
    
        iex> update_user_password(user, %{password: ...})
        {:ok, {%User{}, [...]}}
    
        iex> update_user_password(user, %{password: "too short"})
        {:error, %Ecto.Changeset{}}
    
    
  """
  @spec update_user_password(Gamend.Accounts.User.t(), map()) ::
          {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
          | {:error, Ecto.Changeset.t()}
  def update_user_password(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Accounts.update_user_password/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates the user's unique username handle and broadcasts the change.
    
    Strict, unlike registration: an invalid or taken username returns
    `{:error, changeset}` with no generated fallback, so the player can pick
    again. Routed through the `before_user_update` hook pipeline, where games
    can forbid changes entirely or reject names (profanity, reserved words).
    
  """
  @spec update_username(Gamend.Accounts.User.t(), map()) ::
          {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_username(_user, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Accounts.User{
           id: 0,
           email: "",
           display_name: nil,
           metadata: %{},
           is_admin: false,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Accounts.update_username/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns true when the given user is activated or when account activation
    is not required. Returns false only when activation is required **and**
    the user's `is_activated` flag is `false`.
    
  """
  @spec user_activated?(Gamend.Accounts.User.t()) :: boolean()
  def user_activated?(_user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.user_activated?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether an account with this id exists.
    
    For the contexts that write a row pointing at a user, before they write it.
    SQLite — the default adapter — does not report *which* constraint an
    `INSERT` violated, only that one was violated, so
    `Ecto.Changeset.foreign_key_constraint/2` cannot match it and Ecto raises
    `Ecto.ConstraintError` instead of returning a changeset. The declarations in
    those schemas are therefore decorative on SQLite (the adapter's own docs say
    so), and a bad `user_id` reaching the database surfaced as a 500.
    
    Checking first costs one indexed read and gives the caller a real answer.
    It is not a substitute for the foreign key: the row can still be deleted
    between this and the write. That race ends where it did before, which is why
    the constraint stays declared.
    
    Returns `false` for a malformed id rather than raising, since these ids come
    from request bodies and hook arguments.
    
    Goes through `get_user/1` rather than a bare `Repo.exists?`, because this sits
    on the hot write paths — a currency grant, a score submission — and
    `get_user/1` is cached. A player earning currency during a session was
    authenticated moments ago, so their row is already in the cache and this costs
    nothing; `Repo.exists?` would take a connection from the pool every time.
    Correctness is unchanged: `delete_user/1` invalidates that entry, and a
    `nil` lookup is never cached (`cache_match/1`), so a missing user is re-checked
    against the database each time rather than being remembered as absent.
    
  """
  @spec user_exists?(term()) :: boolean()
  def user_exists?(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.user_exists?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Map of `%{id => %User{}}` for the given ids, for batch name lookups (e.g. admin
    tables that hold only a `user_id`). Nil/duplicate ids are ignored.
    
  """
  @spec users_by_ids([Ecto.UUID.t()]) :: %{required(Ecto.UUID.t()) => Gamend.Accounts.User.t()}
  def users_by_ids(_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Accounts.users_by_ids/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns true when `password` matches the user's current password.
    
  """
  @spec valid_password?(Gamend.Accounts.User.t(), term()) :: boolean()
  def valid_password?(_user, _password) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Accounts.valid_password?/2 is a stub - only available at runtime on Gamend"
    end
  end
end
