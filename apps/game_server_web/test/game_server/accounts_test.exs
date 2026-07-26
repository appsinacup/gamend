defmodule GameServer.AccountsTest do
  use GameServer.DataCase

  alias GameServer.Accounts

  import GameServer.AccountsFixtures
  alias GameServer.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "users_by_ids/1" do
    test "maps ids to users, ignoring nils and duplicates" do
      u1 = user_fixture()
      u2 = user_fixture()

      result = Accounts.users_by_ids([u1.id, u2.id, nil, u1.id])

      assert %User{} = result[u1.id]
      assert %User{} = result[u2.id]
      assert map_size(result) == 2
    end

    test "returns an empty map when given no ids" do
      assert Accounts.users_by_ids([nil]) == %{}
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert user.is_admin
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    test "registers user with device_id set" do
      device_id = "test-device-#{System.unique_integer([:positive])}"

      attrs =
        valid_user_attributes(%{"password" => valid_user_password(), "device_id" => device_id})

      {:ok, user} = Accounts.register_user(attrs)

      assert user.device_id == device_id
    end

    test "register_user_and_deliver/3 succeeds when notifier delivers" do
      # ensure there's already a user so we are not the first user (first user is auto-admin and skips email delivery)
      _existing = user_fixture()

      email = unique_user_email()
      attrs = valid_user_attributes(%{"email" => email})

      defmodule SuccessNotifier do
        def deliver_confirmation_instructions(_user, _url), do: {:ok, :sent}
      end

      {:ok, user} =
        Accounts.register_user_and_deliver(attrs, fn t -> "http://x/#{t}" end, SuccessNotifier)

      assert Repo.get_by(Accounts.User, id: user.id)
      assert Repo.get_by(Accounts.UserToken, user_id: user.id)
    end

    test "register_user_and_deliver/3 rolls back when notifier fails" do
      _existing = user_fixture()

      email = unique_user_email()
      attrs = valid_user_attributes(%{"email" => email})

      defmodule FailNotifier do
        def deliver_confirmation_instructions(_user, _url), do: {:error, :smtp_failed}
      end

      assert {:error, :smtp_failed} =
               Accounts.register_user_and_deliver(
                 attrs,
                 fn t -> "http://x/#{t}" end,
                 FailNotifier
               )

      refute Repo.get_by(Accounts.User, email: email)
    end
  end

  describe "find_or_create_from_device/2" do
    test "makes the first device user admin" do
      device_id = "test-device-#{System.unique_integer([:positive])}"

      assert {:ok, user} = Accounts.find_or_create_from_device(device_id)
      assert user.is_admin
    end

    test "does not make later device users admin" do
      _existing = user_fixture()
      device_id = "test-device-#{System.unique_integer([:positive])}"

      assert {:ok, user} = Accounts.find_or_create_from_device(device_id)
      refute user.is_admin
    end

    test "delete_user clears device_id cache (delete then login recreates user)" do
      _existing = user_fixture()
      device_id = "test-device-#{System.unique_integer([:positive])}"

      assert {:ok, user1} = Accounts.find_or_create_from_device(device_id)

      # Second call hits the lookup path and populates the device_id cache.
      assert {:ok, ^user1} = Accounts.find_or_create_from_device(device_id)

      assert {:ok, _} = Accounts.delete_user(user1)
      refute Repo.get(User, user1.id)

      # If the cache wasn't cleared synchronously, this can return a stale user struct
      # that no longer exists in the DB.
      assert {:ok, user2} = Accounts.find_or_create_from_device(device_id)
      assert Repo.get(User, user2.id)
      assert user2.id != user1.id
      assert user2.device_id == device_id
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "short",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 8 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "bumps token_version to revoke issued JWTs", %{user: user} do
      {:ok, {updated, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert updated.token_version == user.token_version + 1
    end
  end

  describe "revoke_all_tokens/1" do
    setup do
      %{user: user_fixture()}
    end

    test "deletes session tokens and bumps token_version", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {updated, expired_tokens}} = Accounts.revoke_all_tokens(user)

      assert length(expired_tokens) == 1
      refute Repo.get_by(UserToken, user_id: user.id)
      assert updated.token_version == user.token_version + 1
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user/1 and lobby/token cleanup" do
    test "deleting a host with other members transfers host and deletes tokens" do
      # create host and member
      host = user_fixture() |> set_password()
      member = user_fixture()

      {:ok, lobby} =
        GameServer.Lobbies.create_lobby(%{title: "hosted", host_id: host.id})

      # add member to lobby
      {:ok, _} = GameServer.Lobbies.create_membership(%{lobby_id: lobby.id, user_id: member.id})

      # ensure session token exists for host
      _token = Accounts.generate_user_session_token(host)

      # delete host
      assert {:ok, _} = Accounts.delete_user(host)

      # host removed
      refute Repo.get(Accounts.User, host.id)

      # tokens removed for host
      refute Repo.get_by(Accounts.UserToken, user_id: host.id)

      # lobby should still exist and transfer host to member
      updated = Repo.get!(GameServer.Lobbies.Lobby, lobby.id)
      assert updated.host_id == member.id
    end

    test "deleting last member host deletes lobby and tokens" do
      host = user_fixture() |> set_password()

      {:ok, lobby} =
        GameServer.Lobbies.create_lobby(%{title: "single", host_id: host.id})

      # create a token for the host
      _t = Accounts.generate_user_session_token(host)

      assert {:ok, _} = Accounts.delete_user(host)

      # host and lobby gone
      refute Repo.get(Accounts.User, host.id)
      refute Repo.get(GameServer.Lobbies.Lobby, lobby.id)

      # tokens removed
      refute Repo.get_by(Accounts.UserToken, user_id: host.id)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "search_users/2" do
    test "returns empty list for blank query" do
      assert Accounts.search_users("") == []
      assert Accounts.search_users("   ") == []
    end

    test "finds user by display_name prefix" do
      user = user_fixture()
      {:ok, _} = Accounts.update_user_display_name(user, %{"display_name" => "AlphaPlayer"})

      results = Accounts.search_users("alpha")
      assert results != []
      assert Enum.any?(results, &(&1.id == user.id))
    end

    test "treats LIKE wildcards in the query literally" do
      user = user_fixture()
      {:ok, _} = Accounts.update_user_display_name(user, %{"display_name" => "WildcardName"})

      # "%" and "_" must not act as wildcards
      refute Enum.any?(Accounts.search_users("%"), &(&1.id == user.id))
      refute Enum.any?(Accounts.search_users("_ildcard"), &(&1.id == user.id))
    end

    test "does not find user by email prefix" do
      user_fixture(%{email: "private-search@example.com", display_name: "PublicName"})

      assert Accounts.search_users("private-search") == []
    end

    test "serialize_brief omits email" do
      user = user_fixture(%{email: "brief-private@example.com", display_name: "BriefName"})

      refute Map.has_key?(User.serialize_brief(user), :email)
      refute Map.has_key?(Jason.decode!(Jason.encode!(user)), "email")
    end

    test "numeric query returns both ID match and display_name matches" do
      # Create a user whose display_name starts with a digit
      user_with_numeric_name = user_fixture()

      {:ok, _} =
        Accounts.update_user_display_name(user_with_numeric_name, %{
          "display_name" => "#{user_with_numeric_name.id}player"
        })

      # Create another user whose display_name also starts with the same digits
      other_user = user_fixture()

      {:ok, _} =
        Accounts.update_user_display_name(other_user, %{
          "display_name" => "#{user_with_numeric_name.id}gamer"
        })

      query = to_string(user_with_numeric_name.id)
      results = Accounts.search_users(query)

      # Should include the ID-matched user
      assert Enum.any?(results, &(&1.id == user_with_numeric_name.id))
      # Should also include text matches (display_name starts with the same digits)
      assert Enum.any?(results, &(&1.id == other_user.id))
      # No duplicates
      ids = Enum.map(results, & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "numeric query returns ID match even without text match" do
      user = user_fixture()
      {:ok, _} = Accounts.update_user_display_name(user, %{"display_name" => "NoDigitsHere"})

      query = to_string(user.id)
      results = Accounts.search_users(query)

      assert Enum.any?(results, &(&1.id == user.id))
    end
  end

  describe "count_search_users/1" do
    test "returns 0 for blank query" do
      assert Accounts.count_search_users("") == 0
    end

    test "numeric query counts both ID and text matches without double-counting" do
      user = user_fixture()

      {:ok, _} =
        Accounts.update_user_display_name(user, %{"display_name" => "#{user.id}name"})

      other = user_fixture()

      {:ok, _} =
        Accounts.update_user_display_name(other, %{"display_name" => "#{user.id}other"})

      query = to_string(user.id)
      count = Accounts.count_search_users(query)
      search_count = length(Accounts.search_users(query))

      # count should match the actual number of results from search_users
      assert count == search_count
    end
  end

  describe "list_all_users/2 (admin search) and its boundary with search_users/2" do
    test "finds a user by full id" do
      target = user_fixture()
      other = user_fixture()

      ids = Accounts.list_all_users(%{search: target.id}) |> Enum.map(& &1.id)
      assert target.id in ids
      refute other.id in ids
    end

    test "admin search matches sensitive fields like email; player search does not" do
      user = user_fixture()
      email = user.email

      # Admin can find by email.
      assert Accounts.list_all_users(%{search: email}) |> Enum.any?(&(&1.id == user.id))

      # Privacy boundary: the public player search must NOT match email.
      refute Accounts.search_users(email) |> Enum.any?(&(&1.id == user.id))
    end

    test "facets filter (online) and count agree with the listing" do
      online = user_fixture()
      {:ok, _} = online |> Ecto.Changeset.change(is_online: true) |> GameServer.Repo.update()
      _offline = user_fixture()

      filters = %{facets: ["online"]}
      listed = Accounts.list_all_users(filters, page_size: 100)

      assert Enum.all?(listed, & &1.is_online)
      assert online.id in Enum.map(listed, & &1.id)
      assert Accounts.count_list_all_users(filters) == length(listed)
    end
  end
end
