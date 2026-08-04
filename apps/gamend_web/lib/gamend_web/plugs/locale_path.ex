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
      conn = fetch_session(conn)

      case classify(conn) do
        {:serve_localized, locale, rest, clean_path} ->
          # Serve at the prefixed URL. The router sees the clean path; the
          # browser and the crawler keep `/es/about`.
          GamendWeb.GettextSync.put_locale(locale)

          %{conn | path_info: rest}
          |> put_session(@session_key, locale)
          |> assign(:locale, locale)
          |> assign(:locale_prefix, locale)
          |> assign(:seo_path, clean_path)

        {:redirect, locale, redirect_path} ->
          # Store locale in session and redirect to the unprefixed URL.
          # This avoids LiveView WebSocket URL mismatches.
          conn
          |> put_session(@session_key, locale)
          |> Phoenix.Controller.redirect(to: redirect_path)
          |> halt()

        :no_prefix ->
          conn
          |> apply_session_locale()
          |> assign(:seo_path, conn.request_path)
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
  Gettext locales use `_` (`pt_BR`); BCP-47, which `hreflang` requires, uses
  `-` (`pt-BR`). URLs emit the BCP-47 form.
  """
  @spec url_locale(String.t()) :: String.t()
  def url_locale(locale), do: String.replace(locale, "_", "-")

  defp classify(%Plug.Conn{path_info: [first | rest]} = conn) when is_binary(first) do
    case GamendWeb.GettextSync.normalize_locale(first) do
      locale when is_binary(locale) and locale in @known_locales ->
        clean_path =
          case rest do
            [] -> "/"
            _ -> "/" <> Enum.join(rest, "/")
          end

        cond do
          # The default locale never gets a prefix of its own — it would be a
          # duplicate of the clean URL.
          locale == @default_locale ->
            {:redirect, locale, with_query(clean_path, conn.query_string)}

          localized_path?(clean_path) ->
            {:serve_localized, locale, rest, clean_path}

          true ->
            {:redirect, locale, with_query(clean_path, conn.query_string)}
        end

      _ ->
        :no_prefix
    end
  end

  defp classify(_conn), do: :no_prefix

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

  # Read locale from session (set by a prior redirect) or fall back to default.
  defp apply_session_locale(conn) do
    locale =
      conn
      |> get_session(@session_key)
      |> GamendWeb.GettextSync.normalize_locale()
      |> Kernel.||(@default_locale)

    GamendWeb.GettextSync.put_locale(locale)
    assign(conn, :locale, locale)
  end
end
