defmodule GameServer.Tournaments.Match do
  @moduledoc """
  A pairing plus a verdict: two entries that must produce a winner by
  `deadline_at`. Never a lobby — how the pairing is played is game policy;
  `metadata` is game scratch space (runs, lobby id, ...).
  """

  use GameServer.Schema
  import Ecto.Changeset

  schema "tournament_matches" do
    belongs_to :tournament, GameServer.Tournaments.Tournament
    belongs_to :a_entry, GameServer.Tournaments.Entry
    belongs_to :b_entry, GameServer.Tournaments.Entry
    belongs_to :winner_entry, GameServer.Tournaments.Entry

    field :bracket_index, :integer
    field :round, :integer
    field :slot, :integer
    field :ready_at, :utc_datetime
    field :expired_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :deadline_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :tournament_id,
      :bracket_index,
      :round,
      :slot,
      :a_entry_id,
      :b_entry_id,
      :winner_entry_id,
      :ready_at,
      :expired_at,
      :resolved_at,
      :deadline_at,
      :metadata
    ])
    |> validate_required([:tournament_id, :bracket_index, :round, :slot, :deadline_at])
    |> unique_constraint([:tournament_id, :bracket_index, :round, :slot])
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end
end
