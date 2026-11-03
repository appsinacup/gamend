defmodule Gamend.Repo.Migrations.CreateNotificationDigestItems do
  @moduledoc """
  `notification_digest_items` (`Gamend.Notifications.Digest`): the notices
  waiting for a user's next digest email. A row goes when its digest is sent.
  The in-app table cannot hold them: it keeps one row per title, so a run of
  notices leaves only the last.
  """

  use Ecto.Migration

  def change do
    create table(:notification_digest_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :group_key, :string, null: false
      add :subject, :text, null: false
      add :text, :text, null: false, default: ""
      add :url, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notification_digest_items, [:user_id, :group_key])
  end
end
