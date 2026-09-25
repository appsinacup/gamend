defmodule Gamend.Repo.Migrations.CreateApiTokens do
  @moduledoc """
  Personal API tokens (`Gamend.Accounts.ApiTokens`): long-lived bearer tokens
  for scripts and CI, created on the settings page.

  Only a SHA-256 of each token is stored, under a unique index, so a request
  is one indexed lookup and a leaked database holds nothing a client could
  send. `token_version` is the owner's at creation: a password or email change
  bumps the user's, which retires every token made before it.
  """
  use Ecto.Migration

  def change do
    create table(:api_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :hint, :string, null: false
      add :token_version, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:user_id])
    create index(:api_tokens, [:expires_at], where: "expires_at IS NOT NULL")
  end
end
