defmodule GameServer.Friends.Friendship do
  @moduledoc """
  Ecto schema representing a friendship/request between two users.

  The friendship object stores the requester and the target user together with
  a status field which can be "pending", "accepted", "rejected" or
  "blocked".
  """
  use GameServer.Schema
  import Ecto.Changeset

  alias GameServer.Accounts.User

  @statuses ["pending", "accepted", "rejected", "blocked"]

  @derive {Jason.Encoder,
           only: [
             :id,
             :requester_id,
             :target_id,
             :status,
             :inserted_at,
             :updated_at
           ]}

  schema "friendships" do
    belongs_to :requester, User
    belongs_to :target, User

    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  @typedoc "A friendship/request record between two users."
  @type t :: %__MODULE__{
          id: integer() | nil,
          requester_id: integer() | nil,
          target_id: integer() | nil,
          status: String.t()
        }

  @doc false
  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:requester_id, :target_id, :status])
    |> validate_required([:requester_id, :target_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_requester_target_diff()
    |> unique_constraint([:requester_id, :target_id], name: :unique_requester_target)
  end

  defp validate_requester_target_diff(changeset) do
    requester = get_field(changeset, :requester_id)
    target = get_field(changeset, :target_id)

    if requester && target && requester == target do
      add_error(changeset, :target_id, "cannot friend yourself")
    else
      changeset
    end
  end
end
