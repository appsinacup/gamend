defmodule Gamend.Repo.Migrations.CreateLoginLockouts do
  @moduledoc """
  Failed password sign-ins per email address (`Gamend.Accounts.LoginLockouts`),
  and the lock they set once there are too many.

  Keyed by a SHA-256 of the normalized address rather than by user: an address
  with no account counts and locks exactly like one that has an account, so a
  lock never tells anyone which addresses are registered, and the table holds
  no addresses. A row lives for one window of failures, or for the lock it set;
  `Gamend.Retention` prunes it after.
  """
  use Ecto.Migration

  def change do
    create table(:login_lockouts) do
      add :key_hash, :binary, null: false
      add :failures, :integer, null: false, default: 0
      add :window_started_at, :utc_datetime, null: false
      add :locked_until, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:login_lockouts, [:key_hash])
    create index(:login_lockouts, [:updated_at])
  end
end
