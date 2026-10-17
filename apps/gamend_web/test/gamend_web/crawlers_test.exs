defmodule GamendWeb.CrawlersTest do
  @moduledoc """
  `GamendWeb.Crawlers`: a person from a crawler by user-agent, and a claimed
  search crawler against its engine's DNS (`GamendWeb.Crawlers.Verify`).
  """
  use ExUnit.Case, async: false

  alias GamendWeb.Crawlers
  alias GamendWeb.Crawlers.Verify

  doctest GamendWeb.Crawlers

  # Real agents, as the crawlers and browsers send them.
  @agents [
    {"Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.6668.89 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
     {:search, "Googlebot"}},
    {"Googlebot-Image/1.0", {:search, "Googlebot"}},
    {"Mozilla/5.0 (compatible; Google-InspectionTool/1.0;)", {:search, "Google-InspectionTool"}},
    {"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm) Chrome/116.0.1938.76 Safari/537.36",
     {:search, "Bingbot"}},
    {"Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)", {:search, "YandexBot"}},
    {"Mozilla/5.0 (compatible; YandexImages/3.0; +http://yandex.com/bots)",
     {:search, "YandexBot"}},
    {"Mozilla/5.0 (compatible; SeznamBot/4.0; +https://o-seznam.cz/napoveda/vyhledavani/en/seznambot-crawler/)",
     {:search, "SeznamBot"}},
    {"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15 (Applebot/0.1; +http://www.apple.com/go/applebot)",
     {:search, "Applebot"}},
    {"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; OAI-SearchBot/1.0; +https://openai.com/searchbot",
     {:ai_search, "OAI-SearchBot"}},
    {"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; GPTBot/1.2; +https://openai.com/gptbot",
     {:ai_training, "GPTBot"}},
    {"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ClaudeBot/1.0; +claudebot@anthropic.com)",
     {:ai_training, "ClaudeBot"}},
    {"Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Claude-SearchBot/1.0; +Claude-SearchBot@anthropic.com)",
     {:ai_search, "Claude-SearchBot"}},
    {"Mozilla/5.0 (Linux; Android 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36 (compatible; Bytespider; spider-feedback@bytedance.com)",
     {:ai_training, "Bytespider"}},
    {"Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)", {:seo, "AhrefsBot"}},
    {"facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
     {:unfurler, "facebookexternalhit"}},
    {"Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)",
     {:unfurler, "Discordbot"}},
    # Telegram names Twitterbot after itself: the leftmost token wins.
    {"TelegramBot (like TwitterBot)", {:unfurler, "TelegramBot"}},
    {"Mozilla/5.0 (compatible; archive.org_bot +http://archive.org/details/archive.org_bot)",
     {:archive, "archive.org_bot"}},
    {"Mozilla/5.0+(compatible; UptimeRobot/2.0; http://www.uptimerobot.com/)",
     {:monitor, "UptimeRobot"}},
    {"curl/8.4.0", {:other_bot, "curl"}},
    {"python-requests/2.31.0", {:other_bot, "python"}},
    {"Go-http-client/1.1", {:other_bot, "go"}},
    {"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0.0.0 Safari/537.36",
     {:other_bot, "headless browser"}},
    {"Mozilla/5.0 (compatible; FooCrawler/1.0; +https://example.com/bot)",
     {:other_bot, "other bot"}},
    {"something", {:other_bot, "unrecognised client"}},
    {"", {:other_bot, "no user-agent"}},
    {nil, {:other_bot, "no user-agent"}},
    # People
    {"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36",
     {:human, nil}},
    {"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
     {:human, nil}},
    {"Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0", {:human, nil}},
    # A phone maker whose name ends in "bot", and the Yandex app (not its crawler).
    {"Mozilla/5.0 (Linux; Android 10; CUBOT X30) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
     {:human, nil}},
    {"Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 YaBrowser/24.1 YandexSearch/24.1 Mobile Safari/537.36",
     {:human, nil}},
    {"GodotEngine/4.3.stable (Windows)", {:human, nil}}
  ]

  test "classifies real user-agents" do
    for {agent, expected} <- @agents do
      assert Crawlers.classify(agent) == expected, "#{inspect(agent)}"
    end
  end

  test "every name and kind is in the closed set" do
    kinds = Crawlers.kinds()

    for {agent, _} <- @agents do
      {kind, name} = Crawlers.classify(agent)
      assert kind in kinds
      assert is_nil(name) or byte_size(name) <= 32
      assert Crawlers.crawler?(kind) == (kind != :human)
      assert is_binary(Crawlers.label(kind))
    end
  end

  test "every name Verify checks is a search crawler the classifier names" do
    for name <- Verify.checked_names() do
      assert {name, :search} in Crawlers.known(), name
    end
  end

  describe "DNS check" do
    defmodule FakeDNS do
      @moduledoc false
      # 66.249.66.1 is Google's; 203.0.113.7 claims to be and is not;
      # 198.51.100.1 has no PTR; 192.0.2.1 times out.
      def reverse({66, 249, 66, 1}), do: {:ok, ["crawl-66-249-66-1.googlebot.com."]}
      def reverse({203, 0, 113, 7}), do: {:ok, ["crawl-66-249-66-1.googlebot.com.evil.example"]}
      def reverse({198, 51, 100, 1}), do: {:error, :nxdomain}
      def reverse({192, 0, 2, 1}), do: {:error, :timeout}

      def forward("crawl-66-249-66-1.googlebot.com", :inet), do: [{66, 249, 66, 1}]
      def forward(_host, _family), do: []
    end

    setup do
      previous = Application.get_env(:gamend_web, Crawlers, [])

      Application.put_env(
        :gamend_web,
        Crawlers,
        previous |> Keyword.put(:resolver, FakeDNS) |> Keyword.put(:verify, true)
      )

      Verify.init_table()
      Verify.reset()

      on_exit(fn ->
        Application.put_env(:gamend_web, Crawlers, previous)
        Verify.reset()
      end)
    end

    test "check/2 reads the PTR and confirms it forward" do
      google = ~w(googlebot.com google.com)
      assert Verify.check({66, 249, 66, 1}, google) == :verified
      assert Verify.check({203, 0, 113, 7}, google) == :impostor
      assert Verify.check({198, 51, 100, 1}, google) == :impostor
      assert Verify.check({192, 0, 2, 1}, google) == {:error, :timeout}
    end

    test "status/2 answers unverified, then the background verdict" do
      assert Verify.status("Googlebot", {203, 0, 113, 7}) == :unverified
      assert eventually(fn -> Verify.status("Googlebot", {203, 0, 113, 7}) == :impostor end)

      assert Verify.status("Googlebot", {66, 249, 66, 1}) == :unverified
      assert eventually(fn -> Verify.status("Googlebot", {66, 249, 66, 1}) == :verified end)

      # A DNS failure is not a verdict.
      Verify.status("Googlebot", {192, 0, 2, 1})
      Process.sleep(50)
      assert Verify.status("Googlebot", {192, 0, 2, 1}) == :unverified

      # A name with no published domain is never checked.
      assert Verify.status("DuckDuckBot", {203, 0, 113, 7}) == :unverified
    end

    test "classify_conn/1 turns a failed check into an impostor" do
      agent = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

      conn = fn ip ->
        :get
        |> Plug.Test.conn("/")
        |> Map.put(:remote_ip, ip)
        |> Plug.Conn.put_req_header("user-agent", agent)
      end

      Crawlers.classify_conn(conn.({203, 0, 113, 7}))

      assert eventually(fn ->
               Crawlers.classify_conn(conn.({203, 0, 113, 7})) == {:impostor, "Googlebot"}
             end)

      Crawlers.classify_conn(conn.({66, 249, 66, 1}))
      Process.sleep(50)
      assert Crawlers.classify_conn(conn.({66, 249, 66, 1})) == {:search, "Googlebot"}
    end

    test "an IPv4 client on a dual-stack listener is checked as IPv4" do
      mapped = {0, 0, 0, 0, 0, 0xFFFF, 66 * 256 + 249, 66 * 256 + 1}
      Verify.status("Googlebot", mapped)
      assert eventually(fn -> Verify.status("Googlebot", mapped) == :verified end)
    end
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, tries - 1)
    end
  end
end
