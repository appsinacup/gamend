defmodule GameServer.Accounts.User do
  @moduledoc """
  The User schema and associated changeset functions used across the
  application (registration, OAuth, and admin changes).

  This module keeps Ecto changesets for common user interactions and
  validations so other domains can reuse them safely.
  """
  @typedoc "The public user struct used across the application."
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | integer() | nil,
          email: String.t() | nil,
          hashed_password: String.t() | nil,
          confirmed_at: DateTime.t() | nil,
          username: String.t() | nil,
          display_name: String.t() | nil,
          metadata: map(),
          lobby_id: integer() | nil,
          party_id: integer() | nil,
          is_online: boolean(),
          last_seen_at: DateTime.t() | nil
        }
  use GameServer.Schema
  import Ecto.Changeset

  @last_seen_fallback ~U[1970-01-01 00:00:00Z]

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :discord_id, :string
    field :profile_url, :string
    field :username, :string
    field :display_name, :string
    field :device_id, :string
    field :apple_id, :string
    field :steam_id, :string
    field :google_id, :string
    field :facebook_id, :string
    field :is_admin, :boolean, default: false
    field :is_activated, :boolean, default: true
    field :metadata, :map, default: %{}
    field :is_online, :boolean, default: false
    field :last_seen_at, :utc_datetime
    field :token_version, :integer, default: 0

    # membership via users.lobby_id (each user can be in one lobby)
    belongs_to :lobby, GameServer.Lobbies.Lobby

    # party membership via users.party_id (each user can be in one party)
    belongs_to :party, GameServer.Parties.Party

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering a new user.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> email_changeset(attrs, opts)
    |> password_changeset(attrs, opts)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: GameServer.Limits.get(:max_email))

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, GameServer.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    min_length = min_password_length()

    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: min_length, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :auth,
    label: "Authentication"

  setting(:min_password_length, :integer,
    default: 8,
    doc: "Minimum password length enforced at registration and change."
  )

  @doc "The minimum password length enforced at registration and change."
  @spec min_password_length() :: pos_integer()
  def min_password_length, do: GameServer.Settings.get(__MODULE__, :min_password_length)

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  A user changeset for Discord OAuth registration.

  It accepts email and Discord fields.
  """
  def discord_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :discord_id, :profile_url, :display_name])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_required([:discord_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: GameServer.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, GameServer.Repo)
    |> unsafe_validate_unique(:discord_id, GameServer.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:discord_id)
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
    |> validate_length(:profile_url, max: GameServer.Limits.get(:max_profile_url))
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for Steam OpenID registration.

  Expects steam_id and optional profile fields.
  """
  def steam_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :steam_id, :profile_url, :display_name])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_required([:steam_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: GameServer.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, GameServer.Repo)
    |> unsafe_validate_unique(:steam_id, GameServer.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:steam_id)
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
    |> validate_length(:profile_url, max: GameServer.Limits.get(:max_profile_url))
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for Apple OAuth registration.

  It accepts email and Apple ID.
  """
  def apple_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :apple_id, :display_name])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_required([:apple_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: GameServer.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, GameServer.Repo)
    |> unsafe_validate_unique(:apple_id, GameServer.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:apple_id)
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for Google OAuth registration.

  It accepts email and Google ID.
  """
  def google_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :google_id, :profile_url, :display_name])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_required([:google_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: GameServer.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, GameServer.Repo)
    |> unsafe_validate_unique(:google_id, GameServer.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
    |> validate_length(:profile_url, max: GameServer.Limits.get(:max_profile_url))
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for Facebook OAuth registration.

  It accepts email and Facebook ID.
  """
  def facebook_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :facebook_id, :profile_url, :display_name])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_required([:facebook_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: GameServer.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, GameServer.Repo)
    |> unsafe_validate_unique(:facebook_id, GameServer.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:facebook_id)
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
    |> validate_length(:profile_url, max: GameServer.Limits.get(:max_profile_url))
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset used for device-based logins where there is no email.

  Device users are created with optional display_name and metadata and are
  immediately confirmed so the SDK can receive tokens without email confirmation.
  """
  def device_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :metadata])
    |> validate_length(:display_name, min: 1, max: GameServer.Limits.get(:max_display_name))
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  Changeset used when a device_id is present (linking device_id to user).
  Ensures device_id is stored on user record and enforces uniqueness by DB
  constraint.
  """
  def attach_device_changeset(user, attrs) do
    user
    |> cast(attrs, [:device_id])
    |> validate_required([:device_id])
    |> validate_length(:device_id, max: GameServer.Limits.get(:max_device_id))
    |> unique_constraint(:device_id)
  end

  @doc """
  A user changeset for admin updates.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:is_admin, :is_activated, :metadata, :display_name])
    |> validate_required([:is_admin])
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  A changeset for the unique username handle.

  Input is lowercased on cast. Valid usernames are 3–32 chars
  (`GameServer.Limits` `:min_username`/`:max_username`) of `a-z`, `0-9` and
  non-consecutive `.` `_` `-` separators, starting and ending alphanumeric.
  Uniqueness is enforced by the DB unique index.
  """
  def username_changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> cast(attrs, [:username])
    |> update_change(:username, fn
      nil -> nil
      username -> String.downcase(username)
    end)
    |> validate_required([:username])
    |> validate_length(:username,
      min: GameServer.Limits.get(:min_username),
      max: GameServer.Limits.get(:max_username)
    )
    |> validate_format(:username, ~r/^[a-z0-9](?:[._-]?[a-z0-9])*$/,
      message:
        "only a-z, 0-9 and non-consecutive . _ - separators; must start and end alphanumeric"
    )
    |> unique_constraint(:username)
  end

  @doc """
  A simple changeset for updating a user's display name.

  Allows empty string so users can set an empty display name if desired.
  """
  def display_name_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, max: GameServer.Limits.get(:max_display_name))
  end

  @doc "Changeset for setting the avatar URL (`profile_url`) from an upload."
  def avatar_changeset(user, attrs) do
    user
    |> cast(attrs, [:profile_url])
    |> validate_length(:profile_url, max: GameServer.Limits.get(:max_profile_url))
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%GameServer.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Returns `last_seen_at` when present, otherwise a stable fallback timestamp.
  """
  @spec last_seen_at_or_fallback(t()) :: DateTime.t()
  def last_seen_at_or_fallback(%__MODULE__{last_seen_at: nil}), do: @last_seen_fallback

  def last_seen_at_or_fallback(%__MODULE__{last_seen_at: %DateTime{} = last_seen_at}),
    do: last_seen_at

  @doc """
  Serialize a user into a compact public map suitable for member lists in parties,
  lobbies, and friends. Includes metadata for rendering player appearance.
  """
  @spec serialize_brief(t()) :: map()
  def serialize_brief(%__MODULE__{} = user) do
    %{
      id: user.id,
      username: user.username || "",
      display_name: user.display_name || "",
      profile_url: user.profile_url || "",
      metadata: user.metadata || %{},
      is_online: user.is_online || false,
      is_activated: user.is_activated,
      last_seen_at: last_seen_at_or_fallback(user)
    }
  end
end

defimpl Jason.Encoder, for: GameServer.Accounts.User do
  def encode(user, opts) do
    %{
      id: user.id,
      username: user.username || "",
      display_name: user.display_name || "",
      profile_url: user.profile_url || "",
      metadata: user.metadata || %{},
      lobby_id: user.lobby_id || "",
      party_id: user.party_id || "",
      is_online: user.is_online || false,
      is_activated: user.is_activated,
      last_seen_at: GameServer.Accounts.User.last_seen_at_or_fallback(user),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
    |> Jason.Encode.map(opts)
  end
end
