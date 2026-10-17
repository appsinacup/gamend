defmodule GamendWeb.Plugs.RateLimiterExemptTest do
  @moduledoc """
  `GAMEND_RATELIMIT_EXEMPT_IPS`: the addresses it names are never throttled,
  every other address still is. For a load test from a known machine: at
  240 a minute a crawler replay from one address was 429 within seconds and
  measured the limiter, not the site (2026-10-08).
  """
  use GamendWeb.ConnCase, async: false

  alias GamendWeb.Plugs.RateLimiter

  @exempt {203, 0, 113, 9}
  @other {203, 0, 113, 10}

  setup do
    previous = Application.get_env(:gamend_web, RateLimiter, [])

    Application.put_env(
      :gamend_web,
      RateLimiter,
      # The test config switches the limiter off; this is a test of it.
      previous
      |> Keyword.put(:enabled, true)
      |> Keyword.put(:general_limit, 2)
      |> Keyword.put(:exempt_ips, " 203.0.113.9, 2001:db8::1 ")
    )

    on_exit(fn -> Application.put_env(:gamend_web, RateLimiter, previous) end)
    :ok
  end

  defp hit(ip) do
    :get
    |> Plug.Test.conn("/")
    |> Map.put(:remote_ip, ip)
    |> RateLimiter.call([])
  end

  test "an exempt address is never throttled" do
    for _ <- 1..10 do
      conn = hit(@exempt)
      refute conn.halted
      refute conn.status == 429
    end
  end

  test "every other address still is" do
    statuses = for _ <- 1..6, do: hit(@other).status
    assert 429 in statuses
  end

  test "an IPv6 address in the list is matched as written" do
    for _ <- 1..10 do
      refute hit({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}).status == 429
    end
  end
end
