defmodule GamendWeb.AccountProtectionTest do
  @moduledoc """
  Per-account lockout after failed passwords, and the grace period before a
  deleted account is gone, as the API and the browser see them.
  """
  # Settings are global Application config.
  use GamendWeb.ConnCase, async: false

  import Gamend.AccountsFixtures

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Repo
  alias Gamend.SettingsHelpers
  alias GamendWeb.Auth.Guardian

  defp put_setting(key, value) do
    SettingsHelpers.put(:gamend_core, Accounts, key, value)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, key) end)
  end

  defp api_login(email, password) do
    post(build_conn(), "/api/v1/login", %{email: email, password: password})
  end

  describe "lockout" do
    setup do
      put_setting(:lockout_attempts, 2)
      %{user: set_password(user_fixture())}
    end

    test "the API answers 429 account_locked with Retry-After, even for the right password",
         %{user: user} do
      assert json_response(api_login(user.email, "wrong password!"), 401)

      locked = api_login(user.email, "wrong password!")
      assert %{"error" => "account_locked"} = json_response(locked, 429)

      conn = api_login(user.email, valid_user_password())
      assert %{"error" => "account_locked"} = json_response(conn, 429)
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) in 1..(15 * 60)
    end

    test "the browser says so, and an emailed link still signs in", %{conn: conn, user: user} do
      for _ <- 1..2 do
        post(build_conn(), ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "wrong password!"}
        })
      end

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many failed attempts"
      refute get_session(conn, :user_token)

      token = extract_user_token(&Accounts.deliver_login_instructions(user, &1))
      conn = post(build_conn(), ~p"/users/log_in", %{"user" => %{"token" => token}})
      assert get_session(conn, :user_token)
    end
  end

  describe "deletion grace period" do
    setup do
      put_setting(:deletion_grace_days, 30)
      %{user: set_password(user_fixture())}
    end

    test "DELETE /me schedules the account and signs it out", %{user: user} do
      {:ok, token, _} = Guardian.encode_and_sign(user)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token)
        |> delete("/api/v1/me", %{current_password: valid_user_password()})

      assert json_response(conn, 200) == %{"ok" => true}
      assert %User{deletion_scheduled_at: %DateTime{}} = Repo.get(User, user.id)

      stale =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token)
        |> get("/api/v1/me")

      assert json_response(stale, 401)
    end

    test "API sign-ins are refused until then", %{user: user} do
      {:ok, {:scheduled, _, _}} = Accounts.request_deletion(user)

      conn = api_login(user.email, valid_user_password())
      assert %{"error" => "deletion_scheduled"} = json_response(conn, 403)
      assert Accounts.deletion_scheduled?(Accounts.get_user!(user.id))
    end

    test "a device sign-in does not undo it" do
      device_id = "device:#{System.unique_integer([:positive])}"
      conn = post(build_conn(), "/api/v1/login/device", %{device_id: device_id})
      %{"data" => %{"user_id" => id}} = json_response(conn, 200)

      {:ok, {:scheduled, _, _}} = Accounts.request_deletion(Accounts.get_user!(id))

      conn = post(build_conn(), "/api/v1/login/device", %{device_id: device_id})
      assert %{"error" => "deletion_scheduled"} = json_response(conn, 403)
    end

    test "signing in on the website keeps the account", %{conn: conn, user: user} do
      {:ok, {:scheduled, _, _}} = Accounts.request_deletion(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "will not be deleted"
      refute Accounts.deletion_scheduled?(Accounts.get_user!(user.id))
    end
  end

  describe "stored objects on a private S3 bucket" do
    setup do
      storage = Application.get_env(:gamend_core, Gamend.Storage, [])
      s3 = Application.get_env(:gamend_core, Gamend.Storage.S3, [])

      Application.put_env(:gamend_core, Gamend.Storage, Keyword.put(storage, :adapter, :s3))

      Application.put_env(
        :gamend_core,
        Gamend.Storage.S3,
        Keyword.merge(s3,
          bucket: "avatars-test",
          access_key_id: "AKIDEXAMPLE",
          secret_access_key: "secret",
          region: "us-east-1"
        )
      )

      on_exit(fn ->
        Application.put_env(:gamend_core, Gamend.Storage, storage)
        Application.put_env(:gamend_core, Gamend.Storage.S3, s3)
      end)
    end

    test "/storage/<key> redirects to a freshly signed link", %{conn: conn} do
      conn = get(conn, "/storage/avatars/some-user/abc.png")

      assert location = redirected_to(conn, 302)
      assert location =~ "avatars-test"
      assert location =~ "avatars/some-user/abc.png"
      assert location =~ "X-Amz-Expires=3600"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=1800"]
    end

    test "keys outside the public prefixes are still not served", %{conn: conn} do
      assert json_response(get(conn, "/storage/backups/db.sql"), 404)
    end

    test "a host can add a prefix of its own", %{conn: conn} do
      SettingsHelpers.put(:gamend_core, Gamend.Storage, :public_prefixes, ["avatars/", "pdf"])
      on_exit(fn -> SettingsHelpers.delete(:gamend_core, Gamend.Storage, :public_prefixes) end)

      assert redirected_to(get(conn, "/storage/pdf/abc123.pdf"), 302) =~ "pdf/abc123.pdf"
      assert json_response(get(build_conn(), "/storage/pdfs-private/x.pdf"), 404)
      assert json_response(get(build_conn(), "/storage/icons/x.png"), 404)
    end
  end

  test "the request body limit is a setting" do
    SettingsHelpers.put(:gamend_web, GamendWeb.Http, :max_body_bytes, 64)
    on_exit(fn -> SettingsHelpers.delete(:gamend_web, GamendWeb.Http, :max_body_bytes) end)

    body = Jason.encode!(%{email: String.duplicate("a", 100) <> "@example.com", password: "x"})

    assert_error_sent 413, fn ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/login", body)
    end
  end

  describe "WebRTC ICE servers" do
    setup do
      webrtc = Application.get_env(:gamend_web, :webrtc, [])
      Application.put_env(:gamend_web, :webrtc, Keyword.delete(webrtc, :ice_servers))
      on_exit(fn -> Application.put_env(:gamend_web, :webrtc, webrtc) end)
    end

    test "STUN by default, TURN from the settings" do
      assert GamendWeb.WebRTC.ice_servers() == [%{urls: ["stun:stun.l.google.com:19302"]}]

      for {key, value} <- [
            turn_urls: ["turn:relay.example.com:3478"],
            turn_username: "game",
            turn_credential: "s3cret"
          ] do
        SettingsHelpers.put(:gamend_web, GamendWeb.WebRTC, key, value)
        on_exit(fn -> SettingsHelpers.delete(:gamend_web, GamendWeb.WebRTC, key) end)
      end

      assert [
               %{urls: ["stun:stun.l.google.com:19302"]},
               %{urls: ["turn:relay.example.com:3478"], username: "game", credential: "s3cret"}
             ] = GamendWeb.WebRTC.ice_servers()
    end

    test "an ice_servers list in the host config wins" do
      Application.put_env(:gamend_web, :webrtc, ice_servers: [%{urls: "stun:own.example"}])
      assert GamendWeb.WebRTC.ice_servers() == [%{urls: "stun:own.example"}]
    end
  end
end
