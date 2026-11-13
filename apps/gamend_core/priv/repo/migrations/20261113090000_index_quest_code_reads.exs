defmodule Gamend.Repo.Migrations.IndexQuestCodeReads do
  @moduledoc """
  The reads of the redemption codes admin page and its export.

  - `quest_progress (code_id, completed_at, id)`: a code's first redeemers
    (`Gamend.Quests.Codes.used_by_codes/2`) come off the index in order, where
    the `(code_id)` one left every row of the code to sort — millions, for a
    public code. It replaces that index, which it covers.
  - `quest_codes (quest_key, inserted_at, id)`: a quest's codes newest first
    (the page) and oldest first (the export, read in batches).
  """
  use Ecto.Migration

  def up do
    create index(:quest_progress, [:code_id, :completed_at, :id],
             where: "code_id IS NOT NULL",
             name: :quest_progress_code_id_completed_at_index
           )

    drop_if_exists index(:quest_progress, [:code_id])

    create index(:quest_codes, [:quest_key, :inserted_at, :id])
  end

  def down do
    drop_if_exists index(:quest_codes, [:quest_key, :inserted_at, :id])
    create index(:quest_progress, [:code_id], where: "code_id IS NOT NULL")

    drop_if_exists index(:quest_progress, [:code_id, :completed_at, :id],
                     name: :quest_progress_code_id_completed_at_index
                   )
  end
end
