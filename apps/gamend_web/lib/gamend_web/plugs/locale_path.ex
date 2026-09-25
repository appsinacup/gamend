defmodule GamendWeb.Plugs.LocalePath do
  @moduledoc """
  Handles the optional locale prefix in the URL path (e.g. `/es/about`).

  Two behaviours, chosen by what the rest of the path points at:

    * **Content pages** — the allowlist in `:localized_paths` — are served
      *at* the prefixed URL with a 200. The prefix is stripped from
      `path_info` before routing, so the router still only ever sees clean
      paths, but the URL stays `/es/about`. That is what makes the Spanish
      version of a page separately indexable: with a redirect there is exactly
      one indexable URL per page no matter how many locales the site is
      translated into. These pages are all controller rendered, so there is no
      LiveView socket that could reconnect at a URL the router does not know.

    * **Everything else** — the LiveView app pages — keeps the original
      behaviour: store the locale in the session and **redirect** to the
      unprefixed path. A LiveView reconnecting at `/es/learning` would hit an
      unmatched route, so those prefixes must not survive routing.

  The default locale is never served under a prefix: `/en/about` redirects to
  `/about` so the two do not compete as duplicates.

  Assigns `:seo_path` (the clean, locale-free path) for the root layout to
  build `rel="canonical"` and the `hreflang` alternates from.

  Known locales are derived from `Gettext.known_locales/1` at compile time.
  """

  import Plug.Conn

  @session_key :preferred_locale
  @default_locale "en"
  @known_locales GamendWeb.GettextSync.known_locales()

  # An explicit "switch to this language" request from the language switcher.
  #
  # Only the default locale needs it, and it needs it badly: every other locale
  # has a prefixed URL that rewrites the session on its way through, while the
  # default locale's URL is the clean one — which `serve_unprefixed/1` bounces
  # straight back to the session's locale. English was therefore unreachable
  # from any translated page. The param says the reader asked for this, so the
  # session is rewritten and they are sent on to the canonical URL; the language
  # never stays in the address.
  @switch_param "setlang"

  # Controller-rendered pages worth indexing per language. A host overrides
  # this with `config :gamend_web, :localized_paths, [...]`.
  #
  # Entries match exactly. A trailing `/*` makes it a subtree ("/vocabulary/*"
  # covers "/vocabulary/es/food"). Exact-by-default matters: `/blog` is worth
  # translating because the index chrome is translated, while `/blog/:slug`
  # is not — the post bodies are English-only markdown, and advertising
  # translations that do not exist invites duplicate-content penalties.
  @default_localized_paths ~w(
    / /about /contact /credits /screenshots /translators
    /blog /changelog /roadmap /privacy /terms /data_deletion
  )

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["api" | _]} = conn, _opts) do
    # API routes never use locale prefixes or sessions — skip entirely
    GamendWeb.GettextSync.put_locale(@default_locale)
    Plug.Conn.assign(conn, :locale, @default_locale)
  end

  def call(conn, _opts) do
    # Skip locale processing for WebSocket upgrades
    if websocket_request?(conn) do
      conn
    else
      conn = conn |> fetch_session() |> fetch_query_params()

      case classify(conn) do
        {:switch, locale, target} ->
          # A switch is per-reader, never a property of the URL: 302 so nothing
          # caches it, and drop the param so the address they land on is the
          # canonical one.
          conn
          |> put_session(@session_key, locale)
          |> put_status(:found)
          |> Phoenix.Controller.redirect(to: target)
          |> halt()

        {:serve_localized, locale, rest, clean_path} ->
          # Serve at the prefixed URL. The router sees the clean path; the
          # browser and the crawler keep `/es/about`.
          GamendWeb.GettextSync.put_locale(locale)

          %{conn | path_info: rest}
          |> put_session(@session_key, locale)
          |> assign(:locale, locale)
          |> assign(:locale_prefix, locale)
          |> assign(:seo_path, clean_path)

        {:redirect, permanence, locale, redirect_path} ->
          # Store locale in session and redirect to the unprefixed URL.
          # This avoids LiveView WebSocket URL mismatches.
          conn
          |> put_session(@session_key, locale)
          |> put_status(redirect_status(permanence))
          |> Phoenix.Controller.redirect(to: redirect_path)
          |> halt()

        :no_prefix ->
          conn
          |> assign(:seo_path, conn.request_path)
          |> serve_unprefixed()
      end
    end
  end

  @doc """
  The locales advertised as `hreflang` alternates.

  Defaults to every known gettext locale; a host narrows it with
  `config :gamend_web, :hreflang_locales, [...]` when some translations are
  too thin to be worth pointing search engines at.
  """
  @spec hreflang_locales() :: [String.t()]
  def hreflang_locales do
    Application.get_env(:gamend_web, :hreflang_locales, @known_locales)
  end

  @doc "The default locale, served without a prefix."
  @spec default_locale() :: String.t()
  def default_locale, do: @default_locale

  @doc """
  The query parameter a language switcher appends to say the reader chose this
  language deliberately. Consumed and dropped by this plug — see `@switch_param`.
  """
  @spec switch_param() :: String.t()
  def switch_param, do: @switch_param

  @doc """
  Gettext locales use `_` (`pt_BR`); BCP-47, which `hreflang` requires, uses
  `-` (`pt-BR`). URLs emit the BCP-47 form.
  """
  @spec url_locale(String.t()) :: String.t()
  def url_locale(locale), do: String.replace(locale, "_", "-")

  @rtl_locales ~w(ar he fa ur)

  @doc """
  Text direction for the `dir` attribute. Right-to-left scripts must mirror
  the page layout (WCAG/i18n); everything else is `ltr`.
  """
  @spec text_direction(String.t()) :: String.t()
  def text_direction(locale) do
    base = locale |> String.replace("-", "_") |> String.split("_") |> hd()
    if base in @rtl_locales, do: "rtl", else: "ltr"
  end

  defp classify(conn) do
    case switch_request(conn) do
      locale when is_binary(locale) -> {:switch, locale, switch_target(conn, locale)}
      nil -> classify_path(conn)
    end
  end

  # Only a locale we actually serve. An unknown value is ignored rather than
  # redirected: a stray `?setlang=xx` on a shared link should render the page,
  # not bounce.
  defp switch_request(conn) do
    with requested when is_binary(requested) <- conn.query_params[@switch_param],
         locale when is_binary(locale) <- GamendWeb.GettextSync.normalize_locale(requested),
         true <- locale in @known_locales do
      locale
    else
      _ -> nil
    end
  end

  # Where the reader lands after switching: the same page under the chosen
  # locale's canonical URL, with any prefix already in the path replaced rather
  # than stacked, and the rest of the query string kept.
  defp switch_target(conn, locale) do
    clean_path =
      case strip_locale_segment(conn.path_info) do
        [] -> "/"
        rest -> "/" <> Enum.join(rest, "/")
      end

    path =
      if locale == @default_locale do
        clean_path
      else
        "/" <> url_locale(locale) <> String.trim_trailing(clean_path, "/")
      end

    with_query(path, drop_switch_param(conn.query_string))
  end

  @doc """
  `path_info` without a leading locale segment (`["ro", "users", "log_in"]` is
  `["users", "log_in"]`), for code that runs before this plug and must see the
  path the router will. `GamendWeb.Plugs.RateLimiter` is one: it runs before
  the body is parsed, which this plug, needing the session, cannot.
  """
  @spec strip_locale([String.t()]) :: [String.t()]
  def strip_locale(path_info) when is_list(path_info), do: strip_locale_segment(path_info)

  defp strip_locale_segment([first | rest]) when is_binary(first) do
    case GamendWeb.GettextSync.normalize_locale(first) do
      locale when is_binary(locale) and locale in @known_locales -> rest
      _ -> [first | rest]
    end
  end

  defp strip_locale_segment(path_info), do: path_info

  defp drop_switch_param(query_string) do
    query_string
    |> String.split("&", trim: true)
    |> Enum.reject(&String.starts_with?(&1, @switch_param <> "="))
    |> Enum.join("&")
  end

  defp classify_path(%Plug.Conn{path_info: [first | rest]} = conn) when is_binary(first) do
    case GamendWeb.GettextSync.normalize_locale(first) do
      locale when is_binary(locale) and locale in @known_locales ->
        clean_path =
          case rest do
            [] -> "/"
            _ -> "/" <> Enum.join(rest, "/")
          end

        cond do
          # The default locale never gets a prefix of its own — it would be a
          # duplicate of the clean URL. That holds whatever `:localized_paths`
          # says, so it is a *permanent* move: a 301 tells a crawler to
          # consolidate the two and stop coming back, where a 302 says the
          # prefixed URL is the real one and is only away for now.
          locale == @default_locale ->
            {:redirect, :permanent, locale, with_query(clean_path, conn.query_string)}

          localized_path?(clean_path) ->
            {:serve_localized, locale, rest, clean_path}

          # Whether this path is served under a prefix is a config decision, so
          # a host that later adds it to `:localized_paths` must not be fighting
          # 301s cached in every browser and crawler that ever saw one.
          true ->
            {:redirect, :temporary, locale, with_query(clean_path, conn.query_string)}
        end

      _ ->
        :no_prefix
    end
  end

  defp classify_path(_conn), do: :no_prefix

  defp redirect_status(:permanent), do: :moved_permanently
  defp redirect_status(:temporary), do: :found

  @doc """
  `path` with its locale prefix removed — the same value `call/2` assigns as
  `:seo_path`, for callers that only have a URL.

  A LiveView is the case this exists for: it never sees the conn, so
  `handle_params`' `uri` is the only place the path survives, and every lookup
  keyed by page (the SEO title, the description) is keyed by the clean one.
  """
  @spec clean_path(String.t()) :: String.t()
  def clean_path(path) when is_binary(path) do
    case path |> String.split("/", trim: true) |> strip_locale_segment() do
      [] -> "/"
      rest -> "/" <> Enum.join(rest, "/")
    end
  end

  @doc """
  Whether `clean_path` is served under locale prefixes — i.e. whether it is
  worth advertising `hreflang` alternates for.
  """
  @spec localized_path?(String.t()) :: boolean()
  def localized_path?(clean_path) when is_binary(clean_path) do
    Enum.any?(localized_paths(), fn entry ->
      if String.ends_with?(entry, "/*") do
        base = String.trim_trailing(entry, "/*")
        clean_path == base or String.starts_with?(clean_path, base <> "/")
      else
        entry == clean_path
      end
    end)
  end

  defp localized_paths do
    Application.get_env(:gamend_web, :localized_paths, @default_localized_paths)
  end

  defp with_query(path, ""), do: path
  defp with_query(path, query), do: path <> "?" <> query

  defp websocket_request?(conn) do
    case Plug.Conn.get_req_header(conn, "upgrade") do
      [upgrade] -> String.downcase(upgrade) == "websocket"
      _ -> false
    end
  end

  # An unprefixed path that *also* has per-locale URLs is the default-locale
  # document, and only that. It used to render in whatever language the session
  # happened to hold, which was wrong twice over: a cache keyed on the URL would
  # serve one visitor's language to the next, and a page whose content depends
  # on a cookie has no stable canonical URL to hand a crawler.
  #
  # A reader who has chosen another language is *sent to that language's URL*
  # rather than served it here, so nobody loses their language — they get an
  # address that names it, which is also the address worth sharing. Crawlers
  # carry no cookie, so they never see the redirect and always get the canonical
  # document.
  #
  # Paths with no localized form (the LiveView app pages) keep reading the
  # session: there is no prefixed URL to send anyone to.
  defp serve_unprefixed(conn) do
    stored = conn |> get_session(@session_key) |> session_locale()

    cond do
      not localized_path?(conn.request_path) ->
        put_locale(conn, stored)

      conn.method == "GET" and stored != @default_locale ->
        conn
        |> Phoenix.Controller.redirect(to: prefixed_path(conn, stored))
        |> halt()

      true ->
        put_locale(conn, @default_locale)
    end
  end

  # `/vocabulary/spanish` + `it` -> `/it/vocabulary/spanish`. The trailing slash
  # goes so that `/` becomes `/it` rather than `/it/`.
  defp prefixed_path(conn, locale) do
    path = "/" <> url_locale(locale) <> String.trim_trailing(conn.request_path, "/")

    with_query(path, conn.query_string)
  end

  defp put_locale(conn, locale) do
    GamendWeb.GettextSync.put_locale(locale)
    assign(conn, :locale, locale)
  end

  # A stored locale that no longer exists falls back to its base language before
  # the default — someone who picked `es_ES` when it was offered should keep
  # getting Spanish after it is retired, not English.
  #
  # Only for session values. `classify/1` deliberately does *not* do this: a
  # path prefix has to match a real locale exactly, or `/es-MX/about` would be
  # served as a 200 and mint an indexable duplicate of a page we never wrote.
  defp session_locale(stored) do
    case GamendWeb.GettextSync.normalize_locale(stored) do
      locale when is_binary(locale) ->
        locale

      nil ->
        with true <- is_binary(stored),
             [base | _] <- String.split(stored, ["_", "-"]),
             locale when is_binary(locale) <- GamendWeb.GettextSync.normalize_locale(base) do
          locale
        else
          _ -> @default_locale
        end
    end
  end
end
