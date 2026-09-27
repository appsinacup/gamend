defmodule Gamend.Accounts.OAuthTest do
  use Gamend.DataCase, async: true

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures

  describe "find_or_create_from_discord/1" do
    test "prefers provider id and updates existing user" do
      user = AccountsFixtures.unconfirmed_user_fixture(%{email: "u1@example.com"})

      # set an existing discord id on the user
      user = Ecto.Changeset.change(user, discord_id: "d_existing") |> Gamend.Repo.update!()

      {:ok, returned} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "d_existing",
          profile_url: "https://cdn.test/avatar.png"
        })

      assert returned.id == user.id
      assert returned.discord_id == "d_existing"
      assert returned.profile_url == "https://cdn.test/avatar.png"
    end

    test "links to existing user by verified email when provider id missing" do
      user = AccountsFixtures.unconfirmed_user_fixture(%{email: "link_me@example.com"})

      {:ok, returned} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "d_link",
          email: "link_me@example.com",
          email_verified: true
        })

      assert returned.id == user.id
      assert returned.discord_id == "d_link"
    end

    # Registered with a password by whoever typed the address, before anyone
    # proved the inbox: the owner's provider sign-in claims the account, and
    # nothing the registrant was given may still open it.
    test "claiming an unconfirmed account drops its password and revokes its tokens" do
      user =
        %{email: "claimed@example.com"}
        |> AccountsFixtures.unconfirmed_user_fixture()
        |> AccountsFixtures.set_password()

      session = Accounts.generate_user_session_token(user)
      version = Accounts.get_user!(user.id).token_version

      {:ok, returned} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "d_claim",
          email: "claimed@example.com",
          email_verified: true
        })

      assert returned.id == user.id
      assert returned.confirmed_at
      refute returned.hashed_password
      assert returned.token_version > version
      assert %{hashed_password: nil, discord_id: "d_claim"} = Accounts.get_user!(user.id)
      refute Accounts.get_user_by_session_token(session)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(
                 "claimed@example.com",
                 AccountsFixtures.valid_user_password()
               )
    end

    test "a confirmed account keeps its password when a provider links to it" do
      user =
        %{email: "kept@example.com"}
        |> AccountsFixtures.user_fixture()
        |> AccountsFixtures.set_password()

      {:ok, returned} =
        Accounts.find_or_create_from_discord(%{
          discord_id: "d_kept",
          email: "kept@example.com",
          email_verified: true
        })

      assert returned.id == user.id
      assert returned.hashed_password

      assert {:ok, _} =
               Accounts.authenticate_by_password(
                 "kept@example.com",
                 AccountsFixtures.valid_user_password()
               )
    end

    test "refuses to link to an existing account when email is unverified" do
      user = AccountsFixtures.unconfirmed_user_fixture(%{email: "victim@example.com"})

      assert {:error, changeset} =
               Accounts.find_or_create_from_discord(%{
                 discord_id: "d_attacker",
                 email: "victim@example.com",
                 email_verified: false
               })

      assert %{email: [_ | _]} = errors_on(changeset)
      # The provider id must not have been attached to the victim's account.
      assert Accounts.get_user!(user.id).discord_id == nil
    end

    test "creates a new user when neither provider nor email matched" do
      # provider only case should create
      {:ok, returned} =
        Accounts.find_or_create_from_discord(%{discord_id: "d_new", display_name: "newuser"})

      assert returned.discord_id == "d_new"
      assert returned.display_name == "newuser"
    end
  end
end
