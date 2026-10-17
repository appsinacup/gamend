defmodule Gamend.Repo.Migrations.CreateReports do
  @moduledoc """
  `reports`: what players report about the game itself — a broken page, a wrong
  word, a bad image (see `Gamend.Reports`). Unlike `chat_reports` there is no
  reported user and no message: what a report is about is a kind's own
  business, kept as a `subject` map plus a `subject_ref` string the queue
  groups duplicates on.

  `user_id` is nil for a report filed without an account. No IP and no visitor
  id is stored: rate limits are counted in memory, and a report says nothing
  about its sender beyond what they chose to type.
  """
  use Ecto.Migration

  def up do
    create table(:reports) do
      add :kind, :string, null: false
      add :topic, :string
      # What duplicates group on, owned by the kind ("ro/1234", "/games").
      add :subject_ref, :string
      add :subject, :map, null: false, default: %{}
      add :data, :map, null: false, default: %{}
      add :description, :text
      add :email, :string
      add :locale, :string
      add :source, :string, null: false, default: "web"
      # Browser, screen size: what a bug report needs and nobody types.
      add :client, :map, null: false, default: %{}
      # `%{"files" => [%{"key", "type", "size"}]}` — a map, not an array
      # column, so SQLite and Postgres store it the same way.
      add :attachments, :map, null: false, default: %{}
      add :user_id, references(:users, on_delete: :nilify_all)
      add :status, :string, null: false, default: "open"
      add :resolved_by, references(:users, on_delete: :nilify_all)
      add :resolution_note, :text
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The queue and the /admin counter.
    create index(:reports, [:status, :inserted_at])
    # "Twelve people reported this word" — and the per-reporter duplicate check.
    create index(:reports, [:kind, :topic, :subject_ref])
    create index(:reports, [:user_id])
    # Retention reads closed reports by when they were closed.
    create index(:reports, [:resolved_at])
    # The daily caps count today's rows.
    create index(:reports, [:inserted_at])
  end

  def down do
    drop table(:reports)
  end
end
