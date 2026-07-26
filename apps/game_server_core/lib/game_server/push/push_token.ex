defmodule GameServer.Push.PushToken do
  @moduledoc """
  Ecto schema for a registered device push token.

  Fields:

  - `user_id` – owner; a user has many devices
  - `token` – the FCM registration token or APNs device token (globally unique)
  - `platform` – `"android"` | `"ios"` | `"web"`
  - `provider` – `"fcm"` | `"apns"`; drives per-token delivery routing
  - `device_id` – optional stable device key so re-registering rotates the
    token in place instead of accumulating rows
  - `disabled_at` – set when the provider reports the token dead (soft-delete)
  - `last_used_at` – bumped on successful delivery
  - `metadata` – optional client info (`app_version`, `locale`, …), size-capped
  """
  use GameServer.Schema
  import Ecto.Changeset

  alias GameServer.Accounts.User

  @platforms ~w(android ios web)
  @providers ~w(fcm apns)

  # FCM documents no hard cap; real tokens are ~160 bytes, APNs 64 hex chars.
  @max_token_length 4096

  schema "push_tokens" do
    belongs_to :user, User

    field :token, :string
    field :platform, :string
    field :provider, :string
    field :device_id, :string
    field :disabled_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @typedoc "A registered device push token."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          token: String.t() | nil,
          platform: String.t() | nil,
          provider: String.t() | nil,
          device_id: String.t() | nil,
          disabled_at: DateTime.t() | nil,
          last_used_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc "The accepted `platform` values."
  @spec platforms() :: [String.t()]
  def platforms, do: @platforms

  @doc "The accepted `provider` values."
  @spec providers() :: [String.t()]
  def providers, do: @providers

  @doc false
  def changeset(push_token, attrs) do
    push_token
    |> cast(attrs, [:user_id, :token, :platform, :provider, :device_id, :metadata])
    |> validate_required([:user_id, :token, :platform, :provider])
    |> validate_length(:token, min: 1, max: @max_token_length)
    |> validate_inclusion(:platform, @platforms)
    |> validate_inclusion(:provider, @providers)
    |> validate_length(:device_id, max: GameServer.Limits.get(:max_device_id))
    |> GameServer.Limits.validate_metadata_size(:metadata)
    |> unique_constraint(:token)
    |> unique_constraint([:user_id, :device_id])
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Push.PushToken do
  def encode(token, opts) do
    GameServer.SchemaJSON.encode(
      token,
      [
        :id,
        :user_id,
        :token,
        :platform,
        :provider,
        :device_id,
        :disabled_at,
        :last_used_at,
        :metadata,
        :inserted_at
      ],
      opts
    )
  end
end
