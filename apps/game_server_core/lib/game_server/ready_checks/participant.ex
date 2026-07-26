defmodule GameServer.ReadyChecks.Participant do
  @moduledoc """
  Ecto schema for one player's answer inside a ready check.

  A row, not a key in a map on the check: answering is then a single-row write,
  so two players answering in the same instant cannot overwrite each other.

  `ticket_id` is set only for matchmaking checks, where the participant's seat
  in the queue has to dissolve with the check.
  """

  use GameServer.Schema

  import Ecto.Changeset

  alias GameServer.Accounts.User
  alias GameServer.Matchmaking.Ticket
  alias GameServer.ReadyChecks.Check

  @type t :: %__MODULE__{}

  @states ~w(pending ready declined timed_out)

  @derive {Jason.Encoder, only: [:id, :ready_check_id, :user_id, :state, :responded_at]}

  schema "ready_check_participants" do
    field :state, :string, default: "pending"
    field :responded_at, :utc_datetime

    belongs_to :ready_check, Check
    belongs_to :user, User
    belongs_to :ticket, Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:ready_check_id, :user_id, :ticket_id, :state, :responded_at])
    |> validate_required([:ready_check_id, :user_id, :state])
    |> validate_inclusion(:state, @states)
    |> foreign_key_constraint(:ready_check_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:ready_check_id, :user_id])
  end

  @doc "The states a participant may be in."
  @spec states() :: [String.t()]
  def states, do: @states
end
