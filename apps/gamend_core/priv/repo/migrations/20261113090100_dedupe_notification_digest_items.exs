defmodule Gamend.Repo.Migrations.DedupeNotificationDigestItems do
  @moduledoc """
  `notification_digest_items` (`Gamend.Notifications.Digest`):

  - one notice per user, group and subject, as the site keeps one row per
    title: a repeat replaces the waiting one's words. Duplicates already
    stored keep the oldest, whose `inserted_at` is the digest's clock.
  - `(group_key, inserted_at)`: what is due, asked of an index instead of
    grouping the whole table every hour.
  - `sweeps`: how many sweeps queued the notice's digest, so one that never
    goes out (an address that bounces) is given up.
  """

  use Ecto.Migration

  def up do
    # Plain SQL both adapters run: a row with an older twin goes.
    execute("""
    DELETE FROM notification_digest_items
    WHERE EXISTS (
      SELECT 1 FROM notification_digest_items AS older
      WHERE older.user_id = notification_digest_items.user_id
        AND older.group_key = notification_digest_items.group_key
        AND older.subject = notification_digest_items.subject
        AND (older.inserted_at < notification_digest_items.inserted_at
             OR (older.inserted_at = notification_digest_items.inserted_at
                 AND older.id < notification_digest_items.id))
    )
    """)

    alter table(:notification_digest_items) do
      add :sweeps, :integer, null: false, default: 0
    end

    # The unique index leads with the old one's columns, so it replaces it.
    drop_if_exists index(:notification_digest_items, [:user_id, :group_key])
    create unique_index(:notification_digest_items, [:user_id, :group_key, :subject])
    create index(:notification_digest_items, [:group_key, :inserted_at])
  end

  def down do
    drop_if_exists index(:notification_digest_items, [:group_key, :inserted_at])
    drop_if_exists index(:notification_digest_items, [:user_id, :group_key, :subject])
    create index(:notification_digest_items, [:user_id, :group_key])

    alter table(:notification_digest_items) do
      remove :sweeps
    end
  end
end
