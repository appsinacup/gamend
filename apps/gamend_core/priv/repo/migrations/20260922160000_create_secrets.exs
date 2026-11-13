defmodule Gamend.Repo.Migrations.CreateSecrets do
  use Ecto.Migration

  @moduledoc """
  Somewhere to keep a customer's credential.

  Core has never stored one: `Gamend.Settings`' `secret: true` only masks a
  value in the admin UI, and those values come from the environment — they are
  the operator's, not a customer's. A host that signs builds, publishes to a
  store or calls somebody's API on their behalf needs a different thing, and
  every fork that grows one would otherwise invent it again.

  Both adapters, as ever: no Postgres-only types, every index named.
  """

  # Drift, accepted (2026-11-13): until 48ba1dbe5 (2026-11-01) this declared
  # its own `:binary_id` key, which SQLite leaves nullable; since, it takes
  # the repo's `migration_primary_key` (`null: false`). SQLite databases
  # created before keep a nullable `id` (see `20260715210000`).
  def change do
    create table(:secrets) do
      # What owns this, without core having to know what that is. A host says
      # `"forge_project"` and its own id; core never resolves either.
      add :scope, :string, null: false
      add :scope_id, :string, null: false
      add :name, :string, null: false

      # The ciphertext and what it takes to open it. The key itself is named
      # rather than stored: `key_id` says which of the configured keys wrote
      # this row, so a rotation can add a key and let old rows be read by the
      # one they were written with instead of rewriting every row at once.
      add :ciphertext, :binary, null: false
      add :iv, :binary, null: false
      add :tag, :binary, null: false
      add :key_id, :string, null: false

      # An HMAC of the plaintext under the encryption key, not a plain digest.
      # A digest of a short secret — a password, a key alias — is a dictionary
      # away from the secret itself, and this is a column an admin page shows.
      # Under HMAC it is useless to anyone without the key, and still answers
      # "is this the same certificate I uploaded last time".
      add :fingerprint, :binary

      # Metadata a person needs to manage a secret they can never read back.
      add :kind, :string
      add :byte_size, :integer
      add :expires_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # One value per name per owner. Setting a secret twice replaces it, which
    # is the only sane reading of "change my certificate".
    create unique_index(:secrets, [:scope, :scope_id, :name],
             name: :secrets_scope_scope_id_name_index
           )

    # Rotation's query: every row not yet written under the current key.
    create index(:secrets, [:key_id], name: :secrets_key_id_index)
  end
end
