defmodule GamendWeb.AbuseLimitsTest do
  @moduledoc """
  Tests for anti-abuse limits: per-user daily chat quota and the concurrent
  WebSocket cap per user.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.ChannelTest, only: [connect: 2]
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.UserSocket

  @endpoint GamendWeb.Endpoint

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp with_limits(overrides, fun) do
    previous = Application.get_env(:gamend_core, Gamend.Limits, [])
    Application.put_env(:gamend_core, Gamend.Limits, previous ++ overrides)
    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)
    fun.()
  end

  describe "daily chat quota" do
    setup do
      previous = Application.get_env(:gamend_web, GamendWeb.Plugs.RateLimiter, [])

      Application.put_env(
        :gamend_web,
        GamendWeb.Plugs.RateLimiter,
        Keyword.put(previous, :enabled, true)
      )

      on_exit(fn ->
        Application.put_env(:gamend_web, GamendWeb.Plugs.RateLimiter, previous)
      end)

      :ok
    end

    test "POST /chat/messages returns 429 once the daily quota is used up", %{conn: conn} do
      with_limits([max_chat_messages_per_day: 2], fn ->
        owner = AccountsFixtures.user_fixture()

        {:ok, group} =
          Groups.create_group(owner.id, %{"title" => "quota-group", "type" => "public"})

        send_message = fn ->
          conn
          |> auth_conn(owner)
          |> post("/api/v1/chat/messages", %{
            chat_type: "group",
            chat_ref_id: group.id,
            content: "hello"
          })
        end

        assert send_message.() |> json_response(201)
        assert send_message.() |> json_response(201)
        assert %{"error" => "chat_daily_limit"} = send_message.() |> json_response(429)
      end)
    end
  end

  describe "concurrent socket cap" do
    test "rejects new sockets once the per-user cap is reached" do
      with_limits([max_sockets_per_user: 2], fn ->
        user = AccountsFixtures.user_fixture()
        {:ok, token, _} = Guardian.encode_and_sign(user)

        assert {:ok, _s1} = connect(UserSocket, %{"token" => token})
        assert {:ok, _s2} = connect(UserSocket, %{"token" => token})
        assert :error = connect(UserSocket, %{"token" => token})

        # a different user is unaffected
        other = AccountsFixtures.user_fixture()
        {:ok, other_token, _} = Guardian.encode_and_sign(other)
        assert {:ok, _} = connect(UserSocket, %{"token" => other_token})
      end)
    end
  end

  describe "IPv6 clients are limited per /64" do
    setup do
      previous = Application.get_env(:gamend_web, GamendWeb.Plugs.RateLimiter, [])

      Application.put_env(
        :gamend_web,
        GamendWeb.Plugs.RateLimiter,
        Keyword.merge(previous, enabled: true, auth_limit: 2, auth_window_ms: 60_000)
      )

      on_exit(fn ->
        Application.put_env(:gamend_web, GamendWeb.Plugs.RateLimiter, previous)
      end)

      :ok
    end

    test "ip_key/1: IPv4 as itself, IPv6 by /64, IPv4-mapped as the IPv4" do
      assert GamendWeb.RateLimit.ip_key({203, 0, 113, 7}) == "203.0.113.7"
      assert GamendWeb.RateLimit.ip_key({0x2001, 0xDB8, 1, 2, 3, 4, 5, 6}) == "2001:db8:1:2::/64"
      assert GamendWeb.RateLimit.ip_key({0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107}) == "203.0.113.7"
      assert GamendWeb.RateLimit.ip_key("2001:db8:1:2:ffff::1") == "2001:db8:1:2::/64"
      assert GamendWeb.RateLimit.ip_key("unknown") == "unknown"
    end

    test "addresses in one /64 share the auth bucket; another /64 does not" do
      login = fn ip ->
        %{build_conn() | remote_ip: ip}
        |> post("/api/v1/login", %{email: "nobody@example.com", password: "wrong password"})
      end

      refute login.({0x2001, 0xDB8, 0xAB, 1, 0, 0, 0, 1}).status == 429
      refute login.({0x2001, 0xDB8, 0xAB, 1, 0xA, 0xB, 0xC, 0xD}).status == 429
      assert login.({0x2001, 0xDB8, 0xAB, 1, 0xF, 0xF, 0xF, 0xF}).status == 429

      refute login.({0x2001, 0xDB8, 0xAB, 2, 0, 0, 0, 1}).status == 429
    end
  end

  describe "the HTTP rate limiter" do
    setup do
      previous = Application.get_env(:gamend_web, GamendWeb.Plugs.RateLimiter, [])

      Application.put_env(
        :gamend_web,
        GamendWeb.Plugs.RateLimiter,
        Keyword.merge(previous, enabled: true, auth_limit: 1, auth_window_ms: 60_000)
      )

      on_exit(fn ->
        Application.put_env(:gamend_web, GamendWeb.Plugs.RateLimiter, previous)
      end)

      :ok
    end

    test "refuses a request over its limit before reading the body" do
      login = fn ip, body ->
        %{build_conn() | remote_ip: ip}
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/login", body)
      end

      ip = {198, 51, 100, 21}
      _ = login.(ip, ~s({"email": "a@example.com", "password": "x"}))

      # Malformed JSON: had the body been parsed first, this would be a 400.
      assert login.(ip, "{not json").status == 429
    end

    test "counts a locale-prefixed browser login against the auth bucket" do
      login = fn ->
        post(%{build_conn() | remote_ip: {198, 51, 100, 22}}, "/ro/users/log_in", %{})
      end

      refute login.().status == 429
      assert login.().status == 429
    end
  end
end
