defmodule Gamend.Tournaments.Entry do
  @moduledoc """
  One side of the bracket: a leader and their tournament progress.

  Core never tracks team rosters — for `team_size > 1` tournaments the team is
  game policy (hooks), optionally stored in `metadata`.
  """

  use Gamend.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  require Gamend.Tournaments.EntryState, as: EntryState

  @states ~w(registered active eliminated winner)

  schema "tournament_entries" do
    belongs_to :tournament, Gamend.Tournaments.Tournament
    belongs_to :leader, Gamend.Accounts.User

    field :seed, :integer
    field :bracket_index, :integer
    field :wins, :integer, default: 0
    field :state, :string, default: EntryState.registered()
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def states, do: @states

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:tournament_id, :leader_id, :seed, :bracket_index, :wins, :state, :metadata])
    |> validate_required([:tournament_id, :leader_id])
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:tournament_id, :leader_id])
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end
end
