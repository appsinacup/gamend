defmodule GamendWeb.LiveNav do
  @moduledoc """
  Moving between LiveView pages over the websocket the page already has.

  A full page load of a LiveView page opens a new websocket (a new TLS
  connection, the upgrade, the join) and mounts the view twice: 420-560 ms on
  production before the page answers a click. Live navigation reuses the open
  socket and mounts once: 130-150 ms. Phoenix does it for a
  `<.link navigate>` into the same `live_session`, but the site's links are
  plain `<a href>` — the navbar, the footer, every menu — because the same
  components render on controller pages too.

  So the browser decides, per click (`live_nav.js`). This module gives it the
  router's GET routes in the router's own order, each with its `live_session`
  (nil for a controller route), and the locale prefixes. A click on a plain
  link from a connected page is made a live link when the first route that
  matches the target is a LiveView in the page's own `live_session`, and the
  locale prefix does not change. A wrong guess costs one round trip: LiveView
  answers a redirect it cannot mount by loading the page.

  Locale copies of LiveView routes (`/ro/courses/:target`) exist so a socket
  can join at a prefixed URL; the table holds the unprefixed routes and says
  which of them have prefixed copies.

  Built once per router build (`:persistent_term`, keyed by the router's MD5,
  so a recompiled router in dev gets a new table) and served by
  `GamendWeb.Plugs.LiveNavTable` at `/gamend/live-nav.json?v=<version>`.
  """

  alias GamendWeb.Plugs.LocalePath

  @path "/gamend/live-nav.json"

  @doc "The table, as served: `%{version: String.t(), json: binary()}`."
  @spec table() :: %{version: String.t(), json: binary()}
  def table do
    # The router the endpoint dispatches to (`GamendWeb.Endpoint`).
    router = Application.get_env(:gamend_web, :router, GamendWeb.Router)
    key = {__MODULE__, router, router.module_info(:md5)}

    case :persistent_term.get(key, nil) do
      nil ->
        table = build(router)
        :persistent_term.put(key, table)
        table

      table ->
        table
    end
  end

  @doc false
  @spec build(module()) :: %{version: String.t(), json: binary()}
  def build(router) do
    prefixes = locale_prefixes()

    routes =
      for %{verb: :get, path: path} = route <- Phoenix.Router.routes(router),
          do: {path, live_session(route)}

    {prefixed, plain} = Enum.split_with(routes, fn {path, _} -> prefixed?(path, prefixes) end)

    prefixed_live =
      for {path, session} <- prefixed, session != nil, into: MapSet.new() do
        {strip_prefix(path), session}
      end

    entries =
      plain
      # The first of two routes with one path is the one the router matches.
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map(fn {path, session} ->
        [path, session && to_string(session), MapSet.member?(prefixed_live, {path, session})]
      end)

    json = Jason.encode!(%{routes: entries, prefixes: prefixes})
    %{version: json |> :erlang.phash2() |> Integer.to_string(36), json: json}
  end

  @doc """
  What the root layout writes for a LiveView page: the table's URL and the
  page's `live_session`. nil for a controller page, which has no socket.
  """
  @spec meta(map()) :: %{url: String.t(), session: String.t()} | nil
  def meta(assigns) do
    case assigns[:conn] do
      %Plug.Conn{private: %{phoenix_live_view: {_view, _opts, %{name: name}}}} ->
        %{url: @path <> "?v=" <> table().version, session: to_string(name)}

      _ ->
        nil
    end
  end

  @doc "The path the table is served at."
  @spec path() :: String.t()
  def path, do: @path

  defp live_session(%{metadata: %{phoenix_live_view: {_view, _action, _opts, %{name: name}}}}),
    do: name

  defp live_session(_route), do: nil

  # The same list the host router generates its locale copies from.
  defp locale_prefixes do
    LocalePath.hreflang_locales()
    |> Enum.reject(&(&1 == LocalePath.default_locale()))
    |> Enum.map(&LocalePath.url_locale/1)
  end

  defp prefixed?(path, prefixes) do
    case String.split(path, "/", parts: 3) do
      ["", first, _rest] -> first in prefixes
      _ -> false
    end
  end

  defp strip_prefix(path) do
    ["", _prefix, rest] = String.split(path, "/", parts: 3)
    "/" <> rest
  end
end
