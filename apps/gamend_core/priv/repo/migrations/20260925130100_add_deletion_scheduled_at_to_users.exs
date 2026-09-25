defmodule Gamend.Repo.Migrations.AddDeletionScheduledAtToUsers do
  @moduledoc """
  `users.deletion_scheduled_at`: when an account whose owner asked to delete it
  is actually deleted, with `GAMEND_AUTH_DELETION_GRACE_DAYS` set. NULL for
  every account not waiting on that, so the index is partial: the retention
  sweep that deletes due accounts reads only the rows that have a date.
  """
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :deletion_scheduled_at, :utc_datetime
    end

    create index(:users, [:deletion_scheduled_at], where: "deletion_scheduled_at IS NOT NULL")
  end

  def down do
    drop index(:users, [:deletion_scheduled_at])

    alter table(:users) do
      remove :deletion_scheduled_at
    end
  end
end
