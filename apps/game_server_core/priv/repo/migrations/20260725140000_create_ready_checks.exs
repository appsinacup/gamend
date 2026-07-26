defmodule GameServer.Repo.Migrations.CreateReadyChecks do
  @moduledoc """
  Ready checks — "these players must each answer before this proceeds"
  (see docs/specs/ready-check.md).

  Participants are rows rather than a map on the check, so one answer is one
  single-row write: no read-modify-write, so two players answering in the same
  instant cannot lose each other's flag.

  `lobby_id` is nullable because a matchmaking check has no lobby yet — the
  group exists only as its tickets. `party_id` is the second subject: a party
  keeps a standing ready board (see docs/specs/ready-check.md). At most one of
  the two is set; both nil means a matchmaking check.
  """
  use Ecto.Migration

  def up do
    create table(:ready_checks) do
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :lobby_id, references(:lobbies, on_delete: :delete_all)
      add :party_id, references(:parties, on_delete: :delete_all)
      add :deadline_at, :utc_datetime
      add :opened_by, references(:users, on_delete: :nilify_all)
      add :reason, :string
      add :resolved_at, :utc_datetime
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    # One open check per lobby. Resolved ones stay as history, so the index is
    # partial rather than a plain unique on lobby_id.
    create unique_index(:ready_checks, [:lobby_id],
             name: :ready_checks_pending_lobby_index,
             where: "status = 'pending' AND lobby_id IS NOT NULL"
           )

    # Same rule for the party board: one open check per party.
    create unique_index(:ready_checks, [:party_id],
             name: :ready_checks_pending_party_index,
             where: "status = 'pending' AND party_id IS NOT NULL"
           )

    # The expiry sweep reads exactly this predicate.
    create index(:ready_checks, [:deadline_at], where: "status = 'pending'")
    create index(:ready_checks, [:status])

    create table(:ready_check_participants) do
      add :ready_check_id, references(:ready_checks, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :ticket_id, references(:matchmaking_tickets, on_delete: :nilify_all)
      add :state, :string, null: false, default: "pending"
      add :responded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ready_check_participants, [:ready_check_id, :user_id])

    # "One open check per player" cannot be an index: it depends on the *check's*
    # status, not the participant's state, and a player who has already answered
    # still belongs to the open check. `open/3` enforces it with a join instead;
    # this index serves that guard and `for_user/1`.
    create index(:ready_check_participants, [:user_id])
  end

  def down do
    drop table(:ready_check_participants)
    drop table(:ready_checks)
  end
end
