defmodule GamendWeb.Crawlers do
  @moduledoc """
  Tells a person from a crawler by the request's `user-agent`, for the
  traffic statistics (`GamendWeb.Plugs.GeoCountry`, Admin → Geo, and the
  `gamend_geo_*` / `gamend_crawler_*` Prometheus metrics).

  `classify/1` answers `{kind, name}`:

    * `:human` — a browser or a game client; `name` is `nil`
    * `:search` — a search index (Googlebot, Bingbot, YandexBot, …)
    * `:ai_search` — an AI answer engine fetching to cite (OAI-SearchBot,
      Claude-SearchBot, PerplexityBot, ChatGPT-User, …)
    * `:ai_training` — a crawler collecting training data (GPTBot,
      ClaudeBot, CCBot, Bytespider, …)
    * `:seo` — an SEO tool (AhrefsBot, SemrushBot, …)
    * `:unfurler` — a link preview (Discordbot, facebookexternalhit, …)
    * `:archive` — a web archive (archive.org_bot)
    * `:monitor` — an uptime check (UptimeRobot, Pingdom, …)
    * `:other_bot` — any other script or crawler, named by a small closed set
      (`"curl"`, `"python"`, `"headless browser"`, `"other bot"`, …)
    * `:impostor` — claims a search engine's name from an address that
      engine's DNS does not vouch for (`GamendWeb.Crawlers.Verify`)

  This describes what a client is, not whether it is welcome: the crawl
  policy is the host's `robots.txt`. Names are a closed set, so they are safe
  as a Prometheus label.

  The match is the LEFTMOST known token in the lowercased agent, the longest
  at a tie (`:binary.match/2` on one compiled pattern, built at boot by
  `init/0`), then the generic markers. A user-agent is whatever the client
  says it is: only `:search` names are checked against DNS, and only when
  `verify` is on.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :crawlers,
    label: "Crawler statistics"

  alias GamendWeb.Crawlers.Verify

  setting(:verify, :boolean,
    default: true,
    doc:
      "Check a request that claims a search engine's crawler (Googlebot, Bingbot, …) against that engine's reverse DNS, and count a failed check as an impostor. One lookup per address and day, in the background."
  )

  @kinds ~w(human search ai_search ai_training seo unfurler archive monitor other_bot impostor)a

  # {token (lowercase, as it appears in the agent), name, kind}
  @bots [
    # Search indexes
    {"googlebot", "Googlebot", :search},
    {"google-inspectiontool", "Google-InspectionTool", :search},
    {"googleother", "GoogleOther", :search},
    {"storebot-google", "Storebot-Google", :search},
    {"adsbot-google", "AdsBot-Google", :search},
    {"mediapartners-google", "Mediapartners-Google", :search},
    {"feedfetcher-google", "Google (other)", :search},
    {"apis-google", "Google (other)", :search},
    {"bingbot", "Bingbot", :search},
    {"bingpreview", "Bingbot", :search},
    {"msnbot", "Bingbot", :search},
    {"adidxbot", "Bingbot", :search},
    {"yandexbot", "YandexBot", :search},
    {"yandeximages", "YandexBot", :search},
    {"yandexmobilebot", "YandexBot", :search},
    {"yandexrenderresourcesbot", "YandexBot", :search},
    {"duckduckbot", "DuckDuckBot", :search},
    {"applebot", "Applebot", :search},
    {"baiduspider", "Baiduspider", :search},
    {"sogou web spider", "Sogou", :search},
    {"seznambot", "SeznamBot", :search},
    {"yahoo! slurp", "Slurp", :search},
    {"yeti/", "Yeti", :search},
    {"mojeekbot", "MojeekBot", :search},
    {"qwantbot", "Qwantbot", :search},
    {"qwantify", "Qwantbot", :search},
    {"kagibot", "Kagibot", :search},
    {"petalbot", "PetalBot", :search},
    {"coccocbot", "coccocbot", :search},
    # AI answer engines: fetch to cite, not to train
    {"oai-searchbot", "OAI-SearchBot", :ai_search},
    {"chatgpt-user", "ChatGPT-User", :ai_search},
    {"claude-searchbot", "Claude-SearchBot", :ai_search},
    {"claude-user", "Claude-User", :ai_search},
    {"perplexitybot", "PerplexityBot", :ai_search},
    {"perplexity-user", "Perplexity-User", :ai_search},
    {"duckassistbot", "DuckAssistBot", :ai_search},
    {"meta-externalfetcher", "Meta-ExternalFetcher", :ai_search},
    {"mistralai-user", "MistralAI-User", :ai_search},
    {"youbot", "YouBot", :ai_search},
    {"google-cloudvertexbot", "Google-CloudVertexBot", :ai_search},
    # AI training
    {"gptbot", "GPTBot", :ai_training},
    {"claudebot", "ClaudeBot", :ai_training},
    {"anthropic-ai", "ClaudeBot", :ai_training},
    {"claude-web", "ClaudeBot", :ai_training},
    {"ccbot", "CCBot", :ai_training},
    {"bytespider", "Bytespider", :ai_training},
    {"amazonbot", "Amazonbot", :ai_training},
    {"meta-externalagent", "Meta-ExternalAgent", :ai_training},
    {"facebookbot", "FacebookBot", :ai_training},
    {"cohere-ai", "cohere-ai", :ai_training},
    {"cohere-training-data-crawler", "cohere-ai", :ai_training},
    {"diffbot", "Diffbot", :ai_training},
    {"ai2bot", "AI2Bot", :ai_training},
    {"timpibot", "Timpibot", :ai_training},
    {"omgili", "omgili", :ai_training},
    {"webzio-extended", "Webzio-Extended", :ai_training},
    {"iaskspider", "iaskspider", :ai_training},
    {"imagesiftbot", "ImagesiftBot", :ai_training},
    # SEO tools
    {"semrushbot", "SemrushBot", :seo},
    {"ahrefsbot", "AhrefsBot", :seo},
    {"ahrefssiteaudit", "AhrefsBot", :seo},
    {"mj12bot", "MJ12bot", :seo},
    {"dotbot", "DotBot", :seo},
    {"blexbot", "BLEXBot", :seo},
    {"dataforseobot", "DataForSeoBot", :seo},
    {"serpstatbot", "serpstatbot", :seo},
    {"barkrowler", "Barkrowler", :seo},
    {"seekportbot", "SeekportBot", :seo},
    {"rogerbot", "rogerbot", :seo},
    {"screaming frog", "Screaming Frog", :seo},
    {"siteauditbot", "SiteAuditBot", :seo},
    # Link previews
    {"twitterbot", "Twitterbot", :unfurler},
    {"facebookexternalhit", "facebookexternalhit", :unfurler},
    {"facebookcatalog", "facebookexternalhit", :unfurler},
    {"discordbot", "Discordbot", :unfurler},
    {"slackbot", "Slackbot", :unfurler},
    {"slack-imgproxy", "Slackbot", :unfurler},
    {"telegrambot", "TelegramBot", :unfurler},
    {"whatsapp", "WhatsApp", :unfurler},
    {"linkedinbot", "LinkedInBot", :unfurler},
    {"redditbot", "redditbot", :unfurler},
    {"pinterestbot", "Pinterestbot", :unfurler},
    {"mastodon", "Mastodon", :unfurler},
    {"bluesky", "Bluesky", :unfurler},
    {"skypeuripreview", "SkypeUriPreview", :unfurler},
    {"embedly", "Embedly", :unfurler},
    {"iframely", "Iframely", :unfurler},
    {"vkshare", "VKShare", :unfurler},
    # Archives
    {"archive.org_bot", "archive.org_bot", :archive},
    {"ia_archiver", "archive.org_bot", :archive},
    # Uptime checks
    {"uptimerobot", "UptimeRobot", :monitor},
    {"pingdom", "Pingdom", :monitor},
    {"statuscake", "StatusCake", :monitor},
    {"betteruptime", "Better Stack", :monitor},
    {"better uptime", "Better Stack", :monitor},
    {"site24x7", "Site24x7", :monitor},
    {"checkly", "Checkly", :monitor},
    {"datadog", "Datadog", :monitor},
    {"blackbox exporter", "Blackbox exporter", :monitor},
    {"kube-probe", "kube-probe", :monitor}
  ]

  # Scripts and unnamed crawlers, matched only when no known token is: the
  # name is the tool family, never the agent's own text, so the set stays
  # closed.
  @generic [
    {"curl/", "curl"},
    {"wget/", "wget"},
    {"python", "python"},
    {"aiohttp", "python"},
    {"httpx", "python"},
    {"scrapy", "python"},
    {"go-http-client", "go"},
    {"java/", "java"},
    {"okhttp", "java"},
    {"apache-httpclient", "java"},
    {"node-fetch", "node"},
    {"undici", "node"},
    {"axios", "node"},
    {"libwww-perl", "perl"},
    {"ruby", "ruby"},
    {"guzzlehttp", "php"},
    {"headlesschrome", "headless browser"},
    {"phantomjs", "headless browser"},
    {"puppeteer", "headless browser"},
    {"playwright", "headless browser"},
    {"zgrab", "scanner"},
    {"masscan", "scanner"},
    {"nmap", "scanner"},
    {"nuclei", "scanner"},
    {"censys", "scanner"},
    {"expanse", "scanner"},
    {"+http", "other bot"},
    {"bot", "other bot"},
    {"crawl", "other bot"},
    {"spider", "other bot"},
    {"scraper", "other bot"},
    {"fetcher", "other bot"}
  ]

  # A browser engine, or a game engine's HTTP client: a person behind it.
  @human_markers ["applewebkit", "gecko", "trident", "presto", "godotengine", "unityplayer"]

  # Agents that hold a marker above by accident ("CUBOT" is a phone maker).
  @false_positives ["cubot"]

  @by_token Map.new(@bots, fn {token, name, kind} -> {token, {kind, name}} end)
  @generic_by_token Map.new(@generic)
  @pattern_key {__MODULE__, :pattern}

  @typedoc "What kind of client sent a request."
  @type kind ::
          :human
          | :search
          | :ai_search
          | :ai_training
          | :seo
          | :unfurler
          | :archive
          | :monitor
          | :other_bot
          | :impostor

  @doc "Every kind, in display order."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Every named crawler as `{name, kind}`, in match order, each once."
  @spec known() :: [{String.t(), kind()}]
  def known, do: @bots |> Enum.map(fn {_token, name, kind} -> {name, kind} end) |> Enum.uniq()

  @doc "Whether a kind is a crawler or script rather than a person."
  @spec crawler?(kind()) :: boolean()
  def crawler?(:human), do: false
  def crawler?(kind) when kind in @kinds, do: true

  @doc "A kind's label for the admin page."
  @spec label(kind()) :: String.t()
  def label(:human), do: "People"
  def label(:search), do: "Search engines"
  def label(:ai_search), do: "AI answer engines"
  def label(:ai_training), do: "AI training"
  def label(:seo), do: "SEO tools"
  def label(:unfurler), do: "Link previews"
  def label(:archive), do: "Archives"
  def label(:monitor), do: "Uptime checks"
  def label(:other_bot), do: "Other bots and scripts"
  def label(:impostor), do: "Fake search bots"

  @doc """
  Compiles the token pattern into `:persistent_term`, once, at boot (called
  from `GamendWeb.HostSupervision` before the endpoint serves). A missing
  pattern is compiled per call, never put from a request.
  """
  @spec init() :: :ok
  def init do
    :persistent_term.put(@pattern_key, compile())
    Verify.init_table()
  end

  @doc """
  The kind and name of the client behind a request, DNS check included
  (`GamendWeb.Crawlers.Verify`): a `:search` name from an address its engine
  does not vouch for is `{:impostor, name}`.
  """
  @spec classify_conn(Plug.Conn.t()) :: {kind(), String.t() | nil}
  def classify_conn(%Plug.Conn{} = conn) do
    agent =
      case Plug.Conn.get_req_header(conn, "user-agent") do
        [agent | _] -> agent
        [] -> nil
      end

    case classify(agent) do
      {:search, name} = claimed ->
        if verify?() and Verify.status(name, conn.remote_ip) == :impostor,
          do: {:impostor, name},
          else: claimed

      other ->
        other
    end
  end

  @doc """
  The kind and name a user-agent claims, without any DNS check.

      iex> GamendWeb.Crawlers.classify("Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)")
      {:search, "Bingbot"}

      iex> GamendWeb.Crawlers.classify("curl/8.4.0")
      {:other_bot, "curl"}
  """
  @spec classify(String.t() | nil) :: {kind(), String.t() | nil}
  def classify(agent) when agent in [nil, ""], do: {:other_bot, "no user-agent"}

  def classify(agent) when is_binary(agent) do
    lowered = agent |> String.downcase() |> drop_false_positives()

    case :binary.match(lowered, pattern()) do
      {at, len} -> Map.fetch!(@by_token, binary_part(lowered, at, len))
      :nomatch -> classify_unknown(lowered)
    end
  end

  defp classify_unknown(lowered) do
    case Enum.find(@generic, fn {token, _name} -> String.contains?(lowered, token) end) do
      {token, _name} -> {:other_bot, Map.fetch!(@generic_by_token, token)}
      nil -> if human?(lowered), do: {:human, nil}, else: {:other_bot, "unrecognised client"}
    end
  end

  defp human?(lowered), do: String.contains?(lowered, @human_markers)

  defp drop_false_positives(lowered) do
    if String.contains?(lowered, @false_positives),
      do: String.replace(lowered, @false_positives, ""),
      else: lowered
  end

  defp pattern do
    case :persistent_term.get(@pattern_key, nil) do
      nil -> compile()
      pattern -> pattern
    end
  end

  defp compile, do: :binary.compile_pattern(Enum.map(@bots, &elem(&1, 0)))

  defp verify?, do: Gamend.Settings.get(__MODULE__, :verify)
end
