defmodule GamendWeb.Api.V1.SessionControllerTest do
  use GamendWeb.ConnCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.Accounts.User
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  @valid_email "testuser@example.com"
  @valid_password "hello world!"

  setup do
    # Create a user with email and hashed password directly
    # This mimics what would happen after email/password registration
    hashed_password = Bcrypt.hash_pwd_salt(@valid_password)

    user = %User{
      email: @valid_email,
      username: "testuser",
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now(:second)
    }

    {:ok, user} = Repo.insert(user)
    %{user: user}
  end

  describe "POST /api/v1/login" do
    test "returns access and refresh tokens on successful login", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      resp = json_response(conn, 200)

      assert %{
               "data" => %{
                 "access_token" => access_token,
                 "refresh_token" => refresh_token,
                 "expires_in" => 900,
                 "user_id" => user_id,
                 "display_name" => _display_name
               }
             } = resp

      assert user_id == user.id

      assert is_binary(access_token)
      assert is_binary(refresh_token)
      assert access_token != refresh_token
    end

    test "returns 403 email_not_confirmed for the right password on an unconfirmed email", %{
      conn: conn,
      user: user
    } do
      user |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()

      conn = post(conn, "/api/v1/login", %{email: @valid_email, password: @valid_password})

      assert %{"error" => "email_not_confirmed", "message" => _} = json_response(conn, 403)
      refute json_response(conn, 403)["data"]
    end

    test "a wrong password on an unconfirmed email is still 401", %{conn: conn, user: user} do
      user |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()

      conn = post(conn, "/api/v1/login", %{email: @valid_email, password: "wrong password!"})

      assert json_response(conn, 401)["error"] == "invalid_credentials"
    end

    test "returns 401 with invalid credentials", %{conn: conn} do
      conn =
        post(conn, "/api/v1/login", %{
          email: "wrong@example.com",
          password: "wrongpassword"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "device login creates and returns tokens", %{conn: conn} do
      device_id = "device:#{System.unique_integer([:positive])}"

      conn = post(conn, "/api/v1/login/device", %{device_id: device_id})

      resp = json_response(conn, 200)

      assert %{
               "data" => %{
                 "access_token" => access_token,
                 "refresh_token" => refresh_token,
                 "expires_in" => 900,
                 "user_id" => device_user_id,
                 "display_name" => _display_name
               }
             } = resp

      assert is_binary(device_user_id) and device_user_id != ""

      assert is_binary(access_token)
      assert is_binary(refresh_token)

      # ensure user record was created and has device_id set
      assert %Gamend.Accounts.User{device_id: ^device_id} =
               Gamend.Repo.get_by(Gamend.Accounts.User, device_id: device_id)
    end

    test "device login returns existing user tokens", %{conn: conn} do
      # Create a user pre-attached to device_id
      device_id = "device_pre_#{System.unique_integer([:positive])}"

      {:ok, user} =
        Gamend.Accounts.register_user(%{
          email: "devuser#{System.unique_integer([:positive])}@example.com",
          password: "longenoughpass"
        })

      # Registration ignores a submitted `device_id` on purpose; attaching one is
      # an authenticated action.
      {:ok, user} = Gamend.Accounts.link_device_id(user, device_id)

      assert user.device_id == device_id

      conn = post(conn, "/api/v1/login/device", %{device_id: device_id})

      resp = json_response(conn, 200)
      assert %{"data" => %{"access_token" => access_token, "user_id" => returned_id}} = resp
      assert returned_id == user.id

      assert is_binary(access_token)
    end
  end

  describe "POST /api/v1/refresh" do
    test "returns new access token with valid refresh token", %{conn: conn, user: user} do
      # Login to get tokens
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"refresh_token" => refresh_token}} = json_response(conn, 200)

      # Use refresh token to get new access token
      conn = build_conn()
      conn = post(conn, "/api/v1/refresh", %{refresh_token: refresh_token})

      resp = json_response(conn, 200)

      assert %{
               "data" => %{
                 "access_token" => new_access_token,
                 "refresh_token" => returned_refresh_token,
                 "user_id" => user_id,
                 "expires_in" => 900,
                 "display_name" => _display_name
               }
             } = resp

      assert is_binary(new_access_token)
      assert returned_refresh_token == refresh_token
      assert user_id == user.id
    end

    test "returns 401 with invalid refresh token", %{conn: conn} do
      conn = post(conn, "/api/v1/refresh", %{refresh_token: "invalid.token.here"})

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns 401 when using access token instead of refresh token", %{conn: conn} do
      # Login to get tokens
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"access_token" => access_token}} = json_response(conn, 200)

      # Try to use access token for refresh (should fail)
      conn = build_conn()
      conn = post(conn, "/api/v1/refresh", %{refresh_token: access_token})

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns 400 when refresh_token is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/refresh", %{})

      assert %{"error" => "missing_param"} = json_response(conn, 400)
    end

    test "returns 401 after a password change revokes the refresh token", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"refresh_token" => refresh_token}} = json_response(conn, 200)

      {:ok, {_user, _tokens}} =
        Gamend.Accounts.update_user_password(user, %{password: "brand new password!"})

      conn = build_conn()
      conn = post(conn, "/api/v1/refresh", %{refresh_token: refresh_token})

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "access token stops working after revoke_all_tokens/1", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"access_token" => access_token}} = json_response(conn, 200)

      authed = fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> get("/api/v1/me")
      end

      assert json_response(authed.(), 200)

      {:ok, {_user, _tokens}} = Gamend.Accounts.revoke_all_tokens(user)

      assert json_response(authed.(), 401)
    end
  end

  describe "token lifetimes" do
    setup do
      accounts = Application.get_env(:gamend_core, Gamend.Accounts, [])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Accounts, accounts) end)
      :ok
    end

    test "login and refresh follow the TTL settings", %{conn: conn} do
      put_accounts_setting(:access_token_ttl_minutes, 2)
      put_accounts_setting(:refresh_token_ttl_days, 7)

      login = post(conn, "/api/v1/login", %{email: @valid_email, password: @valid_password})

      assert %{"data" => %{"access_token" => access, "refresh_token" => refresh} = data} =
               json_response(login, 200)

      assert data["expires_in"] == 120
      assert lifetime(access) == 120
      assert lifetime(refresh) == 7 * 86_400

      refreshed = post(build_conn(), "/api/v1/refresh", %{refresh_token: refresh})

      assert %{"data" => %{"access_token" => new_access, "expires_in" => 120}} =
               json_response(refreshed, 200)

      assert lifetime(new_access) == 120
    end

    test "a TTL below one counts as one", %{conn: conn} do
      put_accounts_setting(:access_token_ttl_minutes, 0)
      put_accounts_setting(:refresh_token_ttl_days, -3)

      login = post(conn, "/api/v1/login", %{email: @valid_email, password: @valid_password})

      assert %{"data" => %{"refresh_token" => refresh, "expires_in" => 60}} =
               json_response(login, 200)

      assert lifetime(refresh) == 86_400
    end
  end

  defp lifetime(token) do
    {:ok, %{"exp" => exp, "iat" => iat}} = Guardian.decode_and_verify(token)
    exp - iat
  end

  defp put_accounts_setting(key, value) do
    existing = Application.get_env(:gamend_core, Gamend.Accounts, [])
    Application.put_env(:gamend_core, Gamend.Accounts, Keyword.put(existing, key, value))
  end

  defmodule FailNotifier do
    def deliver_confirmation_instructions(_user, _url, _code), do: {:error, :smtp_failed}
  end

  defmodule RefuseRegisterHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_user_register(_user, _attrs), do: {:error, "closed beta"}
  end

  # Sends the queued confirmation email; answers the code in it.
  defp emailed_code(email) do
    assert %{success: _} = Oban.drain_queue(queue: :mailers)
    assert_received {:email, %Swoosh.Email{to: [{_, ^email}], text_body: body}}
    [_, code] = Regex.run(~r/^\s*(\d{6})\s*$/m, body)
    code
  end

  defp register_and_get_code(email) do
    assert json_response(post(build_conn(), "/api/v1/register", %{email: email}), 201)
    emailed_code(email)
  end

  defp confirm(email, code, password \\ @valid_password) do
    post(build_conn(), "/api/v1/register/confirm", %{
      email: email,
      code: code,
      password: password
    })
  end

  describe "POST /api/v1/register" do
    setup do
      accounts = Application.get_env(:gamend_core, Gamend.Accounts, [])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Accounts, accounts) end)
      :ok
    end

    test "creates an account without signing it in", %{conn: conn} do
      created = post(conn, "/api/v1/register", %{email: "new@example.com"})

      assert %{"data" => %{"user_id" => user_id, "email_confirmed" => false} = data} =
               json_response(created, 201)

      refute Map.has_key?(data, "access_token")
      refute Map.has_key?(data, "refresh_token")
      refute Repo.get!(User, user_id).hashed_password
    end

    test "the first account is the admin, and confirms by email like any other", %{
      conn: conn,
      user: user
    } do
      Repo.delete!(user)

      created = post(conn, "/api/v1/register", %{email: "first@example.com"})

      assert %{"data" => %{"user_id" => user_id, "email_confirmed" => false}} =
               json_response(created, 201)

      assert %User{is_admin: true} = Repo.get(User, user_id)
      code = emailed_code("first@example.com")
      assert json_response(confirm("first@example.com", code), 200)["data"]["user_id"] == user_id
    end

    test "emails a link and a code, as browser sign-up does", %{conn: conn} do
      post(conn, "/api/v1/register", %{email: "mailed@example.com"})

      assert %{success: 1} = Oban.drain_queue(queue: :mailers)

      assert_received {:email,
                       %Swoosh.Email{subject: "Confirmation instructions", text_body: body}}

      assert body =~ "/users/confirm/"
      assert body =~ ~r/^\s*\d{6}\s*$/m
    end

    test "answers without waiting for the email; a failed send keeps the account", %{conn: conn} do
      notifier = Application.get_env(:gamend_web, :user_notifier)
      Application.put_env(:gamend_web, :user_notifier, __MODULE__.FailNotifier)

      on_exit(fn ->
        if notifier,
          do: Application.put_env(:gamend_web, :user_notifier, notifier),
          else: Application.delete_env(:gamend_web, :user_notifier)
      end)

      created = post(conn, "/api/v1/register", %{email: "bounced@example.com"})

      assert json_response(created, 201)
      assert [job] = all_enqueued(worker: Gamend.Accounts.ConfirmationMailer)
      assert {:error, :smtp_failed} = perform_job(Gamend.Accounts.ConfirmationMailer, job.args)
      assert Repo.get_by(User, email: "bounced@example.com")
    end

    test "a plugin that refuses the sign-up is 403 registration_refused", %{conn: conn} do
      hooks = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, __MODULE__.RefuseRegisterHooks)
      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, hooks) end)

      refused = post(conn, "/api/v1/register", %{email: "beta@example.com"})

      assert %{"error" => "registration_refused", "message" => "closed beta"} =
               json_response(refused, 403)

      refute Repo.get_by(User, email: "beta@example.com")
    end

    test "keeps a username the caller picked", %{conn: conn} do
      created = post(conn, "/api/v1/register", %{email: "named@example.com", username: "quail"})

      assert json_response(created, 201)["data"]["username"] == "quail"
    end

    test "answers 409 for an email already taken", %{conn: conn} do
      taken = post(conn, "/api/v1/register", %{email: @valid_email})

      assert %{"error" => "validation_failed", "errors" => %{"email" => _}} =
               json_response(taken, 409)
    end

    test "answers 400 without an email", %{conn: conn} do
      missing = post(conn, "/api/v1/register", %{password: @valid_password})

      assert json_response(missing, 400)["error"] == "missing_param"
    end

    test "keeps an account awaiting activation but signs nobody in" do
      put_accounts_setting(:require_activation, true)

      code = register_and_get_code("beta@example.com")
      assert %User{is_activated: false} = Repo.get_by(User, email: "beta@example.com")

      # Confirming the email is not activation: that stays an admin's call.
      assert json_response(confirm("beta@example.com", code), 403)["error"] ==
               "account_not_activated"

      assert %User{confirmed_at: %DateTime{}} = Repo.get_by(User, email: "beta@example.com")
    end
  end

  describe "POST /api/v1/register/confirm" do
    setup do
      accounts = Application.get_env(:gamend_core, Gamend.Accounts, [])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Accounts, accounts) end)
      :ok
    end

    test "confirms with the emailed code, sets the password and signs in" do
      code = register_and_get_code("coded@example.com")

      assert %{"data" => %{"access_token" => _, "refresh_token" => _, "user_id" => user_id}} =
               json_response(confirm("coded@example.com", code), 200)

      assert %User{confirmed_at: %DateTime{}} = Repo.get!(User, user_id)

      login =
        post(build_conn(), "/api/v1/login", %{
          email: "coded@example.com",
          password: @valid_password
        })

      assert json_response(login, 200)["data"]["user_id"] == user_id

      # Spent.
      assert json_response(confirm("coded@example.com", code), 401)["error"] == "invalid_code"
    end

    test "a wrong code is 401 invalid_code" do
      code = register_and_get_code("wrong@example.com")
      wrong = if code == "123456", do: "654321", else: "123456"

      assert json_response(confirm("wrong@example.com", wrong), 401)["error"] == "invalid_code"
    end

    test "a refused password is 422, and the code still works" do
      code = register_and_get_code("weak@example.com")

      assert %{"errors" => %{"password" => _}} =
               json_response(confirm("weak@example.com", code, "x"), 422)

      assert json_response(confirm("weak@example.com", code), 200)
    end

    test "the wrong code that locks the address is 429 with retry-after" do
      put_accounts_setting(:lockout_attempts, 1)
      code = register_and_get_code("locked@example.com")
      wrong = if code == "123456", do: "654321", else: "123456"

      locked = confirm("locked@example.com", wrong)

      assert json_response(locked, 429)["error"] == "account_locked"
      assert [_seconds] = get_resp_header(locked, "retry-after")
    end

    test "answers 400 without an email, a code or a password" do
      missing = post(build_conn(), "/api/v1/register/confirm", %{email: "x@example.com"})

      assert json_response(missing, 400)["error"] == "missing_param"
    end
  end

  describe "POST /api/v1/register/resend" do
    test "emails a new code; the newest one confirms" do
      first = register_and_get_code("again@example.com")

      # A minute after the first email, so it is not dropped as a repeat.
      Repo.update_all(Oban.Job,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :minute)]
      )

      resent = post(build_conn(), "/api/v1/register/resend", %{email: "again@example.com"})
      assert json_response(resent, 200) == %{"ok" => true}

      code = emailed_code("again@example.com")

      if code != first do
        assert json_response(confirm("again@example.com", first), 401)
      end

      assert json_response(confirm("again@example.com", code), 200)
    end

    test "answers the same for an address with nothing to confirm" do
      resent = post(build_conn(), "/api/v1/register/resend", %{email: "nobody@example.com"})

      assert json_response(resent, 200) == %{"ok" => true}
      refute_enqueued(worker: Gamend.Accounts.ConfirmationMailer)
    end

    test "answers 400 without an email" do
      missing = post(build_conn(), "/api/v1/register/resend", %{})

      assert json_response(missing, 400)["error"] == "missing_param"
    end
  end

  describe "DELETE /api/v1/logout" do
    test "returns 200 with empty object", %{conn: conn} do
      conn = delete(conn, "/api/v1/logout")

      assert json_response(conn, 200) == %{"ok" => true}
    end
  end
end
