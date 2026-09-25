defmodule Gamend.StableStorageUrlsMigrationTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures

  @migration Gamend.Repo.Migrations.StableStorageUrls

  # The test run migrated the database already, so the module is usually in
  # memory; requiring the file again would redefine it.
  setup_all do
    unless Code.ensure_loaded?(@migration) do
      Code.require_file("priv/repo/migrations/20260925130200_stable_storage_urls.exs")
    end

    :ok
  end

  test "signed S3 links become /storage/<key>, and nothing else changes" do
    signed = AccountsFixtures.user_fixture()
    external = AccountsFixtures.user_fixture()

    key = "avatars/#{signed.id}/abc123.png"

    Repo.update_all(from(u in User, where: u.id == ^signed.id),
      set: [
        profile_url:
          "https://bucket.s3.amazonaws.com/#{key}?X-Amz-Algorithm=AWS4&X-Amz-Signature=deadbeef"
      ]
    )

    Repo.update_all(from(u in User, where: u.id == ^external.id),
      set: [profile_url: "https://cdn.discordapp.com/avatars/1/2.png"]
    )

    Ecto.Migrator.up(Repo, 99_999_999_999_990, @migration, log: false)

    assert Repo.get!(User, signed.id).profile_url == "/storage/" <> key

    assert Repo.get!(User, external.id).profile_url ==
             "https://cdn.discordapp.com/avatars/1/2.png"
  end
end
