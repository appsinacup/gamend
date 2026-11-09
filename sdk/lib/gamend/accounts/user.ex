defmodule Gamend.Accounts.User do
  @moduledoc """
  User struct from Gamend.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - User ID (integer)
  - `email` - User email (string)
  - `username` - Unique username handle (string)
  - `display_name` - Display name (string, optional)
  - `profile_url` - Profile URL/avatar (string, optional)
  - `metadata` - Arbitrary user metadata (map)
  - `is_admin` - Whether the user is an admin (boolean)
  - `is_online` - Whether the user is currently online (boolean)
  - `last_seen_at` - Last seen timestamp (DateTime, optional)
  - `lobby_id` - Current lobby ID (integer, optional)
  - `party_id` - Current party ID (integer, optional)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          username: String.t() | nil,
          display_name: String.t() | nil,
          profile_url: String.t() | nil,
          metadata: map(),
          is_admin: boolean(),
          is_online: boolean(),
          last_seen_at: DateTime.t() | nil,
          lobby_id: integer() | nil,
          party_id: integer() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :email,
    :username,
    :display_name,
    :profile_url,
    :metadata,
    :is_admin,
    :is_online,
    :last_seen_at,
    :lobby_id,
    :party_id,
    :inserted_at,
    :updated_at
  ]

  @doc """
  Builds an email change changeset for a user.

  This function exists in the real Gamend implementation.
  In the SDK it is provided as a stub so documentation references can resolve.
  """
  @spec email_changeset(t(), map(), keyword()) :: no_return()
  def email_changeset(_user, _attrs, _opts) do
    raise "#{__MODULE__}.email_changeset/3 is a stub - only available at runtime on Gamend"
  end

  @doc """
  Builds a password change changeset for a user.

  This function exists in the real Gamend implementation.
  In the SDK it is provided as a stub so documentation references can resolve.
  """
  @spec password_changeset(t(), map(), keyword()) :: no_return()
  def password_changeset(_user, _attrs, _opts) do
    raise "#{__MODULE__}.password_changeset/3 is a stub - only available at runtime on Gamend"
  end

  @doc """
  Whether this is a guest: an account with no email and no sign-in provider,
  only a device or a browser.

  This function exists in the real Gamend implementation.
  In the SDK it is a stub, so a plugin compiles against it.
  """
  @spec anonymous?(t()) :: boolean()
  def anonymous?(%__MODULE__{}), do: :erlang.phash2(make_ref(), 2) == 0
end
