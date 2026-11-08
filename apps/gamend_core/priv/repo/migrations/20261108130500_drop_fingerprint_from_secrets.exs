defmodule Gamend.Repo.Migrations.DropFingerprintFromSecrets do
  @moduledoc """
  `secrets.fingerprint` was an HMAC under the encryption key: the same key for
  two jobs, and a value that changed at every rotation, so it could not answer
  the question it was kept for. Nothing read it.
  """

  use Ecto.Migration

  def change do
    alter table(:secrets) do
      remove :fingerprint, :binary
    end
  end
end
