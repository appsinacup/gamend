defmodule Gamend.Accounts.User do
  @moduledoc """
  The User schema and associated changeset functions used across the
  application (registration, OAuth, and admin changes).

  This module keeps Ecto changesets for common user interactions and
  validations so other domains can reuse them safely.
  """
  @typedoc "The public user struct used across the application."
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          hashed_password: String.t() | nil,
          confirmed_at: DateTime.t() | nil,
          username: String.t() | nil,
          display_name: String.t() | nil,
          # Nil for rows written before the column had a default.
          metadata: map() | nil,
          lobby_id: Ecto.UUID.t() | nil,
          party_id: Ecto.UUID.t() | nil,
          is_online: boolean(),
          last_seen_at: DateTime.t() | nil,
          birth_year: integer() | nil,
          birth_month: integer() | nil,
          age_country: String.t() | nil,
          age_method: String.t() | nil,
          age_locked_at: DateTime.t() | nil,
          account_class: String.t() | nil,
          grandfathered_at: DateTime.t() | nil,
          deletion_scheduled_at: DateTime.t() | nil
        }
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.AgePolicy
  alias Gamend.Accounts.PasswordHash
  alias Gamend.Accounts.Username

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
    field :github_id, :string
    field :is_admin, :boolean, default: false
    field :is_activated, :boolean, default: true
    field :metadata, :map, default: %{}
    field :is_online, :boolean, default: false
    field :last_seen_at, :utc_datetime
    field :token_version, :integer, default: 0

    # Age. Year and month only — never the day; see the migration for why.
    # `account_class` is derived and written by `Gamend.Accounts.AgePolicy`,
    # and `grandfathered_at` marks an account that predates the age gate.
    field :birth_year, :integer
    field :birth_month, :integer
    field :age_country, :string
    field :age_method, :string
    field :age_locked_at, :utc_datetime
    field :account_class, :string, default: "unknown"
    field :grandfathered_at, :utc_datetime

    # Set when the owner asked to delete the account and
    # `auth.deletion_grace_days` makes that wait. See
    # `Gamend.Accounts.request_deletion/1`.
    field :deletion_scheduled_at, :utc_datetime

    # membership via users.lobby_id (each user can be in one lobby)
    belongs_to :lobby, Gamend.Lobbies.Lobby

    # party membership via users.party_id (each user can be in one party)
    belongs_to :party, Gamend.Parties.Party

    timestamps(type: :utc_datetime)
  end

  # Every identity column a user can be reached or recovered by. A device id is
  # not one of them: it is a string the client made up, so an account holding
  # only that is disposable by construction.
  @identity_fields [
    :email,
    :discord_id,
    :apple_id,
    :steam_id,
    :google_id,
    :facebook_id,
    :github_id
  ]

  @doc """
  True when nothing but a device id backs this account.

  Such an account is created by `POST /api/v1/login/device` with no proof of
  anything, costs an attacker one request, and cannot be emailed - which is why
  it is the tier that gets the tighter quotas and the shorter retention window.
  """
  @spec anonymous?(t()) :: boolean()
  def anonymous?(%__MODULE__{} = user) do
    Enum.all?(@identity_fields, &is_nil(Map.fetch!(user, &1)))
  end

  @doc false
  @spec identity_fields() :: [atom()]
  def identity_fields, do: @identity_fields

  @doc """
  Record an age answer.

  Takes a year and a month and nothing finer — a caller that collected a full
  date discards the day before it gets here, so the day is never written and
  never stored. See the migration for why.

  Validation only: whether the answer is *allowed* to replace an existing one is
  `AgePolicy.may_change_age?/4`, and `Accounts.set_age/2` is what asks. A
  changeset that enforced it too would make the rule two things to keep in step.
  """
  def age_changeset(user, attrs) do
    this_year = Date.utc_today().year

    user
    |> cast(attrs, [:birth_year, :birth_month, :age_country, :age_method])
    |> validate_required([:birth_year, :birth_month, :age_method])
    # A person older than the oldest person is a typo or a probe, not an age.
    |> validate_inclusion(:birth_year, (this_year - 120)..this_year)
    |> validate_inclusion(:birth_month, 1..12)
    |> validate_inclusion(:age_method, AgePolicy.methods())
    |> update_change(:age_country, fn
      nil -> nil
      country -> String.upcase(country)
    end)
    |> validate_length(:age_country, is: 2)
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
      |> validate_length(:email, max: Gamend.Limits.get(:max_email))

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Gamend.Repo)
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

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :auth,
    label: "Authentication"

  setting(:min_password_length, :integer,
    default: 8,
    doc: "Minimum password length enforced at registration and change."
  )

  @doc "The minimum password length enforced at registration and change."
  @spec min_password_length() :: pos_integer()
  def min_password_length, do: Gamend.Settings.get(__MODULE__, :min_password_length)

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # bcrypt silently truncates past 72 bytes; Argon2id does not, but the
      # limit stays so a password set today still verifies if a hash written
      # before the switch is ever compared against it.
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, PasswordHash.hash(password))
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

  # The provider owns the avatar URL, not us: Google in particular hands back
  # `picture` URLs that run past max_profile_url. Rejecting the changeset over
  # one failed the whole sign-in ("Failed to create user from Google:
  # [profile_url: ...]") for a purely cosmetic field, and truncating a URL only
  # produces one that 404s — so drop it and let the account through without a
  # picture. avatar_changeset/2 keeps its hard validation: there the URL comes
  # from the user, so it is ours to reject.
  defp discard_oversized_profile_url(changeset) do
    case get_change(changeset, :profile_url) do
      url when is_binary(url) ->
        if String.length(url) > Gamend.Limits.get(:max_profile_url) do
          delete_change(changeset, :profile_url)
        else
          changeset
        end

      _ ->
        changeset
    end
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
    |> validate_length(:email, max: Gamend.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, Gamend.Repo)
    |> unsafe_validate_unique(:discord_id, Gamend.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:discord_id)
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> discard_oversized_profile_url()
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
    |> validate_length(:email, max: Gamend.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, Gamend.Repo)
    |> unsafe_validate_unique(:steam_id, Gamend.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:steam_id)
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> discard_oversized_profile_url()
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
    |> validate_length(:email, max: Gamend.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, Gamend.Repo)
    |> unsafe_validate_unique(:apple_id, Gamend.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:apple_id)
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
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
    |> validate_length(:email, max: Gamend.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, Gamend.Repo)
    |> unsafe_validate_unique(:google_id, Gamend.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:google_id)
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> discard_oversized_profile_url()
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
    |> validate_length(:email, max: Gamend.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, Gamend.Repo)
    |> unsafe_validate_unique(:facebook_id, Gamend.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:facebook_id)
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> discard_oversized_profile_url()
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A user changeset for GitHub OAuth registration.

  It accepts email and GitHub ID. The email may be absent: a GitHub App
  without the email permission only sees the public profile.
  """
  def github_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :github_id, :profile_url, :display_name])
    |> update_change(:email, fn
      nil -> nil
      email -> String.downcase(email)
    end)
    |> validate_required([:github_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: Gamend.Limits.get(:max_email))
    |> unsafe_validate_unique(:email, Gamend.Repo)
    |> unsafe_validate_unique(:github_id, Gamend.Repo)
    |> unique_constraint(:email)
    |> unique_constraint(:github_id)
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> discard_oversized_profile_url()
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
    |> validate_length(:display_name,
      min: 1,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Gamend.Limits.validate_metadata_size(:metadata)
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
    |> validate_length(:device_id, max: Gamend.Limits.get(:max_device_id))
    |> unique_constraint(:device_id)
  end

  @doc """
  A user changeset for admin updates.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:is_admin, :is_activated, :metadata, :display_name])
    |> validate_required([:is_admin])
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  A changeset for the unique username handle.

  Input is NFKC-normalized and lowercased on cast. Valid usernames are 3–32
  characters (`Gamend.Limits` `:min_username`/`:max_username`) of letters and
  digits in one script, or Latin mixed with Chinese, Japanese or Korean,
  joined by non-consecutive `.` `_` `-` separators and starting and ending on
  a letter or digit — `Gamend.Accounts.Username` has the rules and why, and a
  plugin replaces them with the `validate_username/1` hook. Length and the DB
  unique index stay.
  """
  def username_changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> cast(attrs, [:username])
    |> update_change(:username, fn
      nil -> nil
      username -> Username.normalize(username)
    end)
    |> validate_required([:username])
    |> validate_length(:username,
      min: Gamend.Limits.get(:min_username),
      max: Gamend.Limits.get(:max_username)
    )
    |> validate_change(:username, fn :username, username ->
      case Username.validate(username) do
        :ok -> []
        {:error, message} -> [username: message]
      end
    end)
    |> unique_constraint(:username)
  end

  @doc """
  A simple changeset for updating a user's display name.

  Allows empty string so users can set an empty display name if desired.
  """
  def display_name_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name,
      max: Gamend.Limits.get(:max_display_name),
      count: :codepoints
    )
  end

  @doc "Changeset for setting the avatar URL (`profile_url`) from an upload."
  def avatar_changeset(user, attrs) do
    user
    |> cast(attrs, [:profile_url])
    |> validate_length(:profile_url, max: Gamend.Limits.get(:max_profile_url))
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we burn the same
  time a real verification would to avoid timing attacks.
  """
  def valid_password?(%Gamend.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    PasswordHash.verify(password, hashed_password)
  end

  def valid_password?(_, _) do
    PasswordHash.no_user_verify()
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

defimpl Jason.Encoder, for: Gamend.Accounts.User do
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
      last_seen_at: Gamend.Accounts.User.last_seen_at_or_fallback(user),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
    |> Jason.Encode.map(opts)
  end
end
