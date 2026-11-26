defmodule Gamend.Repo.Migrations.CreateSentMessages do
  @moduledoc """
  `sent_messages`: one row per email or push that went out (`Gamend.Sent`),
  for the admin's Sent card. Kept for `GAMEND_RETENTION_SENT_MESSAGES_DAYS`.
  """

  use Ecto.Migration

  def change do
    create table(:sent_messages) do
      add :channel, :string, null: false
      add :kind, :string, null: false
      add :group_key, :string
      add :batch_id, :binary_id
      add :user_id, references(:users, on_delete: :delete_all)
      add :address, :string
      add :subject, :string
      add :body, :map, null: false, default: %{}
      add :status, :string, null: false
      add :reason, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:sent_messages, [:channel, :inserted_at])
    create index(:sent_messages, [:inserted_at])
    create index(:sent_messages, [:batch_id])
    create index(:sent_messages, [:user_id])
  end
end
