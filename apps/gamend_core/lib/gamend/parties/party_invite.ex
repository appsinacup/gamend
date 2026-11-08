defmodule Gamend.Parties.PartyInvite do
  @moduledoc """
  Ecto schema for the `party_invites` table.

  Stores pending, accepted, declined, and cancelled invitations for parties.
  Unlike the previous approach (which stored invites as notifications),
  invite records are independent of the notification system — deleting
  notifications does not affect pending invites.

  ## Statuses

  - `"pending"`   – waiting for the recipient to decide
  - `"accepted"`  – recipient joined the party
  - `"declined"`  – recipient declined the invite
  - `"cancelled"` – sender cancelled the invite
  """
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Parties.Party

  require Gamend.Parties.PartyInviteStatus, as: PartyInviteStatus

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder,
           only: [
             :id,
             :party_id,
             :sender_id,
             :recipient_id,
             :status,
             :inserted_at,
             :updated_at
           ]}

  schema "party_invites" do
    belongs_to :party, Party
    belongs_to :sender, User
    belongs_to :recipient, User

    field :status, :string, default: PartyInviteStatus.pending()

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(party_id sender_id recipient_id)a
  @optional_fields ~w(status)a

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, PartyInviteStatus.all())
    |> unique_constraint([:sender_id, :recipient_id],
      name: :party_invites_sender_id_recipient_id_index
    )
  end
end
