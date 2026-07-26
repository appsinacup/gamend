defmodule GameServer.Repo.Migrations.RenameDeadlineToDeadlineAt do
  use Ecto.Migration

  # Instants are named `*_at` (docs/specs/api-conventions.md, R3). These two
  # were the only `:utc_datetime` columns that were not.
  #
  # The create-table migrations were edited to say `deadline_at` directly, so
  # a *fresh* database never has a `deadline` column and a bare `rename` here
  # crashes on first migrate (CI, new installs). Only databases that migrated
  # before the rename carry the old name — so rename only when it exists.
  def up do
    rename_if_exists(:ready_checks, "deadline", "deadline_at")
    rename_if_exists(:tournament_matches, "deadline", "deadline_at")
  end

  def down do
    rename_if_exists(:ready_checks, "deadline_at", "deadline")
    rename_if_exists(:tournament_matches, "deadline_at", "deadline")
  end

  defp rename_if_exists(table, from, to) do
    if column_exists?(table, from) do
      execute("ALTER TABLE #{table} RENAME COLUMN #{from} TO #{to}")
    end
  end

  defp column_exists?(table, column) do
    %{rows: rows} =
      case repo().__adapter__() do
        Ecto.Adapters.SQLite3 ->
          repo().query!(
            "SELECT 1 FROM pragma_table_info(?) WHERE name = ?",
            [to_string(table), column]
          )

        _postgres ->
          repo().query!(
            "SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2",
            [to_string(table), column]
          )
      end

    rows != []
  end
end
