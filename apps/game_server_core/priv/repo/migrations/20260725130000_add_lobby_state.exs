defmodule GameServer.Repo.Migrations.AddLobbyState do
  @moduledoc """
  Server-owned lobby lifecycle field (see docs/specs/lobby-state.md).

  `state` carries a game-defined vocabulary — core only sets `"created"` on
  insert and validates against core defaults plus what a plugin declares. It is
  deliberately not an enum/check constraint: games ship their own states.
  """
  use Ecto.Migration

  def up do
    alter table(:lobbies) do
      add :state, :string, null: false, default: "created"
      add :state_changed_at, :utc_datetime
    end

    create index(:lobbies, [:state])

    # Existing rows predate the column; their creation is the only state change
    # that ever happened to them.
    execute("UPDATE lobbies SET state_changed_at = inserted_at WHERE state_changed_at IS NULL")
  end

  def down do
    drop index(:lobbies, [:state])

    alter table(:lobbies) do
      remove :state
      remove :state_changed_at
    end
  end
end
