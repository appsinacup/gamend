defmodule Gamend.Groups.GroupInvite do
  @moduledoc """
  Ecto schema for the `group_invites` table.

  Stores pending, accepted, declined, and cancelled invitations for **hidden**
  groups. Unlike the previous approach (which stored invites as notifications),
  invite records are independent of the notification system — deleting
  notifications does not affect pending invites.

  ## Statuses

  - `"pending"`   – waiting for the recipient to decide
  - `"accepted"`  – recipient joined the group
  - `"declined"`  – recipient declined the invite
  - `"cancelled"` – sender cancelled the invite
  """
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Groups.Group

  require Gamend.Groups.GroupInviteStatus, as: GroupInviteStatus

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder,
           only: [
             :id,
             :group_id,
             :sender_id,
             :recipient_id,
             :status,
             :inserted_at,
             :updated_at
           ]}

  schema "group_invites" do
    belongs_to :group, Group
    belongs_to :sender, User
    belongs_to :recipient, User

    field :status, :string, default: GroupInviteStatus.pending()

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(group_id sender_id recipient_id)a
  @optional_fields ~w(status)a

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, GroupInviteStatus.all())
    |> unique_constraint([:recipient_id, :group_id],
      name: :group_invites_recipient_id_group_id_index
    )
  end
end
