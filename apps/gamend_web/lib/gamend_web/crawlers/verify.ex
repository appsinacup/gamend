defmodule GamendWeb.Crawlers.Verify do
  @moduledoc """
  Whether a request that names a search engine's crawler comes from that
  engine, by the check the engines publish: the address's reverse DNS ends
  in the engine's domain, and that name resolves back to the address.

  Scrapers send `Googlebot` in their user-agent because sites let Googlebot
  in. Without the check, the crawler statistics count them as Google.

  Never on the request path: `status/2` reads the cache and, on a miss,
  starts one background lookup for that address and name, answering
  `:unverified` until it lands. At most `@max_inflight` lookups run at once
  and the cache holds at most `@max_entries`; past either the address stays
  unverified. A result is kept a day; a DNS failure (timeout, server error)
  is not a verdict and is retried after five minutes.

  Only names with a published domain are checked; the rest (DuckDuckBot,
  Kagibot, …) are always `:unverified`.
  """

  require Logger

  @table :crawler_verify
  @day_ms 24 * 60 * 60 * 1000
  @retry_ms 5 * 60 * 1000
  @pending_ms 30_000
  @max_inflight 16
  @max_entries 50_000

  # The domains each engine's crawlers reverse-resolve to.
  @domains %{
    "Googlebot" => ~w(googlebot.com google.com googleusercontent.com),
    "Google-InspectionTool" => ~w(googlebot.com google.com),
    "GoogleOther" => ~w(googlebot.com google.com googleusercontent.com),
    "Storebot-Google" => ~w(googlebot.com google.com),
    "AdsBot-Google" => ~w(googlebot.com google.com),
    "Mediapartners-Google" => ~w(googlebot.com google.com),
    "Google (other)" => ~w(googlebot.com google.com googleusercontent.com),
    "Bingbot" => ~w(search.msn.com),
    "YandexBot" => ~w(yandex.ru yandex.net yandex.com),
    "Applebot" => ~w(applebot.apple.com),
    "Baiduspider" => ~w(baidu.com baidu.jp),
    "Sogou" => ~w(sogou.com),
    "SeznamBot" => ~w(seznam.cz),
    "Slurp" => ~w(crawl.yahoo.net),
    "Yeti" => ~w(naver.com),
    "PetalBot" => ~w(petalsearch.com aspiegel.com)
  }

  @doc "Creates the cache table. Called once at boot by `GamendWeb.Crawlers.init/0`."
  @spec init_table() :: :ok
  def init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    end

    :ok
  end

  @doc "The names this module can check."
  @spec checked_names() :: [String.t()]
  def checked_names, do: Map.keys(@domains)

  @doc """
  The cached verdict for `name` from `ip`: `:verified`, `:impostor`, or
  `:unverified` (not checkable, not checked yet, or DNS failed). A miss
  starts a background lookup.
  """
  @spec status(String.t(), :inet.ip_address() | term()) :: :verified | :impostor | :unverified
  def status(name, ip) do
    with domains when is_list(domains) <- Map.get(@domains, name),
         ip when is_tuple(ip) <- normalize(ip),
         true <- :ets.whereis(@table) != :undefined do
      key = {ip, name}
      now = now_ms()

      case :ets.lookup(@table, key) do
        [{^key, verdict, expires}] when expires > now ->
          if verdict == :pending, do: :unverified, else: verdict

        _ ->
          start_lookup(key, domains, now)
          :unverified
      end
    else
      _ -> :unverified
    end
  end

  @doc """
  Runs the check now, in the caller: `:verified`, `:impostor`, or
  `{:error, reason}` when DNS could not answer.
  """
  @spec check(:inet.ip_address(), [String.t()]) :: :verified | :impostor | {:error, term()}
  def check(ip, domains) do
    case resolver().reverse(ip) do
      {:ok, hosts} ->
        hosts
        |> Enum.map(&normalize_host/1)
        |> Enum.filter(&under?(&1, domains))
        |> Enum.any?(fn host -> ip in resolver().forward(host, family(ip)) end)
        |> if(do: :verified, else: :impostor)

      {:error, :nxdomain} ->
        :impostor

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Drops expired verdicts. Called periodically by `GamendWeb.GeoCountryCleaner`."
  @spec cleanup() :: non_neg_integer()
  def cleanup do
    if :ets.whereis(@table) == :undefined do
      0
    else
      now = now_ms()
      :ets.select_delete(@table, [{{{:_, :_}, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    end
  end

  @doc "Empties the cache (tests, the admin Reset)."
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp start_lookup(key, domains, now) do
    :ets.delete(@table, key)

    if :ets.info(@table, :size) < @max_entries and
         :ets.insert_new(@table, {key, :pending, now + @pending_ms}) do
      if :ets.update_counter(@table, :inflight, {2, 1}, {:inflight, 0}) > @max_inflight do
        :ets.update_counter(@table, :inflight, {2, -1})
        :ets.delete(@table, key)
      else
        Task.start(fn -> run_lookup(key, domains) end)
      end
    end
  end

  defp run_lookup({ip, name} = key, domains) do
    {verdict, ttl} =
      case check(ip, domains) do
        {:error, reason} ->
          Logger.info(
            "crawler DNS check for #{name} from #{:inet.ntoa(ip)} failed: #{inspect(reason)}"
          )

          {:unverified, @retry_ms}

        verdict ->
          {verdict, @day_ms}
      end

    :ets.insert(@table, {key, verdict, now_ms() + ttl})
  after
    :ets.update_counter(@table, :inflight, {2, -1})
  end

  defp under?(host, domains),
    do: Enum.any?(domains, &(host == &1 or String.ends_with?(host, "." <> &1)))

  defp normalize_host(host),
    do: host |> to_string() |> String.downcase() |> String.trim_trailing(".")

  # An IPv4 client on a dual-stack listener arrives as `::ffff:a.b.c.d`; its
  # reverse DNS is the IPv4 one.
  defp normalize({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: {Bitwise.bsr(hi, 8), Bitwise.band(hi, 0xFF), Bitwise.bsr(lo, 8), Bitwise.band(lo, 0xFF)}

  defp normalize(ip) when tuple_size(ip) in [4, 8], do: ip
  defp normalize(_ip), do: nil

  defp family(ip) when tuple_size(ip) == 4, do: :inet
  defp family(_ip), do: :inet6

  defp resolver do
    :gamend_web
    |> Application.get_env(GamendWeb.Crawlers, [])
    |> Keyword.get(:resolver, GamendWeb.Crawlers.DNS)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
