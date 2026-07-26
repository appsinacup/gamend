defmodule GameServer.OAuthSession do
  @moduledoc """
  Simple Ecto schema for OAuth session polling used by client SDKs.

  OAuth sessions allow multi-step auth flows (popup or mobile) where the SDK
  polls for completion status (pending/completed/failed). The schema stores
  provider-specific data in the `data` field for debugging and eventing.
  """
  use GameServer.Schema
  import Ecto.Changeset

  schema "oauth_sessions" do
    field :session_id, :string
    field :provider, :string
    field :status, :string
    field :data, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @typedoc "A short-lived OAuth session used for polling by SDKs."
  @type t :: %__MODULE__{
          id: integer() | nil,
          session_id: String.t(),
          provider: String.t(),
          status: String.t(),
          data: map()
        }

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:session_id, :provider, :status, :data])
    |> validate_required([:session_id])
    |> unique_constraint(:session_id)
  end
end
