defmodule GamendWeb.Plugs.RequestTimerTest do
  use GamendWeb.ConnCase, async: false

  alias GamendWeb.Plugs.RequestTimer

  setup do
    old = Application.get_env(:gamend_web, :slow_request_threshold_ms, :unset)
    Application.put_env(:gamend_web, :slow_request_threshold_ms, -1.0)

    on_exit(fn ->
      case old do
        :unset -> Application.delete_env(:gamend_web, :slow_request_threshold_ms)
        value -> Application.put_env(:gamend_web, :slow_request_threshold_ms, value)
      end
    end)
  end

  defp slow_log(conn) do
    ExUnit.CaptureLog.capture_log(fn ->
      conn
      |> RequestTimer.call(RequestTimer.init([]))
      |> Plug.Conn.send_resp(200, "")
    end)
  end

  test "Apple's first-sign-in user field is redacted" do
    user =
      ~s({"email":"x7@privaterelay.appleid.com","name":{"firstName":"Ada","lastName":"Byron"}})

    log =
      Plug.Test.conn(:post, "/auth/apple/callback", %{
        "code" => "c-123",
        "state" => "s-456",
        "user" => user
      })
      |> slow_log()

    assert log =~ "Slow Request: POST /auth/apple/callback"
    assert log =~ ~s("user" => "[FILTERED]")
    refute log =~ "privaterelay"
    refute log =~ "Byron"
    refute log =~ "c-123"
  end

  test "a nested user form and email or name fields are redacted" do
    log =
      Plug.Test.conn(:post, "/users/register", %{
        "user" => %{"email" => "ada@example.com", "username" => "ada"},
        "login_email" => "ada@example.com",
        "first_name" => "Ada",
        "phone_number" => "+40 700 000 000",
        "lobby" => "harbour"
      })
      |> slow_log()

    refute log =~ "ada@example.com"
    refute log =~ "Ada"
    refute log =~ "+40"
    assert log =~ ~s("lobby" => "harbour")
  end

  test "keys that only contain a redacted word stay readable" do
    log =
      Plug.Test.conn(:get, "/courses/download?country_code=RO&name=Unit+1&user_count=3")
      |> Plug.Conn.fetch_query_params()
      |> slow_log()

    assert log =~ ~s("country_code" => "RO")
    assert log =~ ~s("name" => "Unit 1")
    assert log =~ ~s("user_count" => "3")
  end
end
