defmodule GamendWeb.Plugs.GeoCountryTest do
  @moduledoc """
  `GeoCountry` counts every request by country AND client kind, so Admin →
  Geo can tell people from crawlers, and counts the rate limiter's 429s by
  the same kind, so it shows who gets throttled.
  """
  use GamendWeb.ConnCase, async: false

  alias GamendWeb.Plugs.GeoCountry
  alias GamendWeb.Plugs.RateLimiter

  @browser "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0"
  @bingbot "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)"
  @gptbot "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; GPTBot/1.2"

  setup do
    GeoCountry.init_table()
    GeoCountry.reset_stats()
    on_exit(&GeoCountry.reset_stats/0)
  end

  defp request(agent, ip \\ {203, 0, 113, 1}) do
    :get
    |> Plug.Test.conn("/")
    |> Map.put(:remote_ip, ip)
    |> Plug.Conn.put_req_header("user-agent", agent)
    |> GeoCountry.call([])
  end

  test "assigns the client class and counts people and crawlers apart" do
    assert request(@browser).assigns.client_class == {:human, nil}
    request(@browser)
    assert request(@bingbot).assigns.client_class == {:search, "Bingbot"}
    request(@gptbot)

    snapshot = GeoCountry.traffic_snapshot()

    assert snapshot.total == 4
    assert snapshot.people == 2
    assert snapshot.crawlers == 2
    assert [%{country: "XX", people: 2, crawlers: 2}] = snapshot.countries
    assert Enum.sort(snapshot.kinds) == [{:ai_training, 1}, {:search, 1}]

    assert %{name: "Bingbot", kind: :search, count: 1, rate_limited: 0} in snapshot.bots
    assert %{name: "GPTBot", kind: :ai_training, count: 1, rate_limited: 0} in snapshot.bots

    assert GeoCountry.total_requests() == 4
    assert GeoCountry.total_requests(traffic: :people) == 2
    assert GeoCountry.country_stats(traffic: :crawlers) == [{"XX", 2}]
    assert GeoCountry.dashboard_stats().crawlers_1h == 2
  end

  test "counts 429s by the class of who was throttled" do
    previous = Application.get_env(:gamend_web, RateLimiter, [])

    Application.put_env(
      :gamend_web,
      RateLimiter,
      previous |> Keyword.put(:enabled, true) |> Keyword.put(:general_limit, 1)
    )

    on_exit(fn -> Application.put_env(:gamend_web, RateLimiter, previous) end)

    bot_ip = {203, 0, 113, 50}
    person_ip = {203, 0, 113, 51}

    for _ <- 1..3, do: @bingbot |> request(bot_ip) |> RateLimiter.call([])
    for _ <- 1..2, do: @browser |> request(person_ip) |> RateLimiter.call([])

    snapshot = GeoCountry.traffic_snapshot()

    assert snapshot.rate_limited == %{people: 1, crawlers: 2}

    assert %{name: "Bingbot", count: 3, rate_limited: 2} =
             Enum.find(snapshot.bots, &(&1.name == "Bingbot"))

    # A 429 is not a request on top of the one already counted.
    assert snapshot.total == 5
  end

  test "windows and cleanup read the minute in every row" do
    request(@browser)
    request(@bingbot)

    assert GeoCountry.traffic_snapshot(window: :hour).total == 2
    assert GeoCountry.cleanup_old_buckets() == 0
    assert GeoCountry.traffic_snapshot(window: :week).total == 2
  end
end
