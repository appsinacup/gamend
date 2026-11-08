defmodule Gamend.Groups.GroupJoinRequest do
  @moduledoc """
  Ecto schema for the `group_join_requests` table.

  Tracks pending, approved and rejected join requests for **private** groups.
  Public groups don't need join requests (direct join). Hidden groups use
  invitations instead.

  ## Statuses

  - `"pending"` – waiting for an admin to decide
  - `"accepted"` – approved (user is added to members)
  - `"rejected"` – declined by an admin
  """
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Groups.Group

  require Gamend.Groups.JoinRequestStatus, as: JoinRequestStatus

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder,
           only: [
             :id,
             :group_id,
             :user_id,
             :status,
             :inserted_at,
             :updated_at
           ]}

  schema "group_join_requests" do
    belongs_to :group, Group
    belongs_to :user, User

    field :status, :string, default: JoinRequestStatus.pending()

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(group_id user_id)a
  @optional_fields ~w(status)a

  def changeset(request, attrs) do
    request
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, JoinRequestStatus.all())
    |> unique_constraint([:group_id, :user_id])
  end
end
