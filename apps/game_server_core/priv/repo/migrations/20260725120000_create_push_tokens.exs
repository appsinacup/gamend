defmodule GameServer.Repo.Migrations.CreatePushTokens do
  @moduledoc """
  Device push tokens (see docs/specs/push.md): one row per registered device,
  routed per row via `provider` ("fcm" | "apns"). Dead tokens are soft-disabled
  (`disabled_at`), never hard-deleted by delivery — only the user or retention
  removes rows.
  """
  use Ecto.Migration

  def change do
    create table(:push_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # FCM registration tokens have no documented length cap; :text avoids
      # the varchar(255) default on Postgres.
      add :token, :text, null: false
      add :platform, :string, null: false
      add :provider, :string, null: false
      add :device_id, :string
      add :disabled_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_tokens, [:token])

    create unique_index(:push_tokens, [:user_id, :device_id], where: "device_id IS NOT NULL")

    # The hot "this user's live devices" lookup (delivery fan-out,
    # has-live-tokens cache miss) and the dashboard live counter.
    create index(:push_tokens, [:user_id],
             name: :push_tokens_live_user_index,
             where: "disabled_at IS NULL"
           )

    # Admin table filters.
    create index(:push_tokens, [:platform])
    create index(:push_tokens, [:provider])

    # Retention sweep: every write path touches updated_at, so "stale" is
    # simply rows untouched for RETENTION_PUSH_TOKENS_DAYS.
    create index(:push_tokens, [:updated_at])
  end
end
