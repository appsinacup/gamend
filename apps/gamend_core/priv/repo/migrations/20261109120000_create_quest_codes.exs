defmodule Gamend.Repo.Migrations.CreateQuestCodes do
  @moduledoc """
  Redemption codes: a way to finish a quest (`Gamend.Quests.redeem_code/2`).

  - `quests.code_only` — a quest nothing but a code can finish.
  - `quest_codes` — the codes. `token` is what people see, `lookup` its
    normalized form and the only column a redeem reads by; unique across
    quests, because the player types only the code.
  - `quest_progress.code_id` — which code a player's row came from.
  """
  use Ecto.Migration

  def change do
    alter table(:quests) do
      add :code_only, :boolean, null: false, default: false
    end

    create table(:quest_codes) do
      add :quest_key,
          references(:quests, column: :key, type: :string, on_delete: :delete_all),
          null: false

      # Text, not :string: a token may be longer than Postgres' varchar(255).
      add :token, :text, null: false
      add :lookup, :text, null: false
      # 1 is single-use, N the first N players, NULL every player once.
      add :max_uses, :integer
      add :uses, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quest_codes, [:lookup])
    create index(:quest_codes, [:quest_key, :status])

    alter table(:quest_progress) do
      add :code_id, references(:quest_codes, on_delete: :nilify_all)
    end

    # Who used this code.
    create index(:quest_progress, [:code_id], where: "code_id IS NOT NULL")
  end
end
