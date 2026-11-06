defmodule Gamend.Repo.Migrations.AddBackfillAndAcceptToMatchmakingTickets do
  @moduledoc """
  Two columns on `matchmaking_tickets`:

    * `lobby_id` — the lobby a ticket fills (backfill): its holder hosts it,
      and a match seats the other players there instead of in a new lobby.
      Nilified when the lobby goes, which makes it an ordinary ticket again.
    * `accept_timeout_ms` — when set, a formed match first asks everyone to
      accept (a ready check of kind `accept`) and seats nobody until all do.
  """

  use Ecto.Migration

  def change do
    alter table(:matchmaking_tickets) do
      add :lobby_id, references(:lobbies, type: :binary_id, on_delete: :nilify_all)
      add :accept_timeout_ms, :integer
    end

    # `on_delete: :nilify_all` scans this column on every lobby deletion.
    create index(:matchmaking_tickets, [:lobby_id])
  end
end
