defmodule Gamend.Repo.Migrations.MoveMatchAcceptToSeatHook do
  @moduledoc """
  Whether a formed match asks its players first is the game's answer now
  (`matchmaking_seat_match/1`), not a field a ticket carries:

    * `matchmaking_tickets.accept_timeout_ms` goes.
    * `ready_checks.seating` keeps where an accepted match will sit
      (`Gamend.MatchSeating.dump/1`). Never sent to clients, unlike
      `metadata`: it can name a hidden lobby.
  """

  use Ecto.Migration

  def change do
    alter table(:matchmaking_tickets) do
      remove :accept_timeout_ms, :integer
    end

    alter table(:ready_checks) do
      add :seating, :map
    end
  end
end
