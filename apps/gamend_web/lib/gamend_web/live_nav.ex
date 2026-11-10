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
  (nil for a controller route) and whether it is for signed-in readers, and
  the locale prefixes. A click on a plain link from a connected page is made a
  live link when the first route that matches the target is a LiveView in the
  page's own `live_session`, and the locale prefix does not change. A wrong
  guess costs one round trip: LiveView answers a redirect it cannot mount by
  loading the page. The sign-in pages are listed as controller pages: they are
  always loaded by a request, which carries the page the reader came from
  (`GamendWeb.UserAuth.store_return_to/2`). So a signed-out reader's click on
  a signed-in page is a request too: its plug keeps that page to come back to.

  A move runs no plugs, so the signed-in pages in the public `live_session`
  (`GamendWeb.Router.Shared.gamend_signed_in_routes/2`) are refused by
  `GamendWeb.UserAuth`'s `:mount_route_scope`, from the pipelines read here
  (`signed_in_only?/1`).

  Locale copies of LiveView routes (`/ro/courses/:target`) exist so a socket
  can join at a prefixed URL; the table holds the unprefixed routes and says
  which of them have prefixed copies.

  Built once per router build (`:persistent_term`, keyed by the router's MD5,
  so a recompiled router in dev gets a new table) and served by
  `GamendWeb.Plugs.LiveNavTable` at `/gamend/live-nav.json?v=<version>`.
  """

  alias Gamend.Accounts.Scope
  alias GamendWeb.Plugs.LocalePath

  @path "/gamend/live-nav.json"

  @type table :: %{version: String.t(), json: binary(), signed_in_only: MapSet.t()}

  @doc "The table of the router the endpoint dispatches to (`GamendWeb.Endpoint`)."
  @spec table() :: table()
  def table, do: table(Application.get_env(:gamend_web, :router, GamendWeb.Router))

  @doc """
  Whether a mounting LiveView's route is piped through
  `:require_authenticated_user`.
  """
  @spec signed_in_only?(Phoenix.LiveView.Socket.t()) :: boolean()
  def signed_in_only?(%Phoenix.LiveView.Socket{} = socket) do
    MapSet.member?(table(socket.router).signed_in_only, {socket.view, socket.assigns.live_action})
  end

  @spec table(module()) :: table()
  defp table(router) do
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
  @spec build(module()) :: table()
  def build(router) do
    prefixes = locale_prefixes()
    gets = for %{verb: :get} = route <- Phoenix.Router.routes(router), do: route

    routes =
      for %{path: path} = route <- gets do
        {path, live_session(route), signed_in_only?(router, path)}
      end

    {prefixed, plain} = Enum.split_with(routes, fn {path, _, _} -> prefixed?(path, prefixes) end)

    prefixed_live =
      for {path, session, _} <- prefixed, session != nil, into: MapSet.new() do
        {strip_prefix(path), session}
      end

    entries =
      plain
      # The first of two routes with one path is the one the router matches.
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map(fn {path, session, signed_in_only} ->
        [
          path,
          session && to_string(session),
          MapSet.member?(prefixed_live, {path, session}),
          signed_in_only
        ]
      end)

    json = Jason.encode!(%{routes: entries, prefixes: prefixes})

    signed_in_only =
      for %{path: path, metadata: %{phoenix_live_view: {view, action, _opts, _session}}} <- gets,
          signed_in_only?(router, path),
          into: MapSet.new() do
        {view, action}
      end

    %{
      version: json |> :erlang.phash2() |> Integer.to_string(36),
      json: json,
      signed_in_only: signed_in_only
    }
  end

  @doc """
  What the root layout writes for a LiveView page: the table's URL, the page's
  `live_session`, and whether its reader is signed in. nil for a controller
  page, which has no socket.
  """
  @spec meta(map()) :: %{url: String.t(), session: String.t(), signed_in: boolean()} | nil
  def meta(assigns) do
    case assigns[:conn] do
      %Plug.Conn{private: %{phoenix_live_view: {_view, _opts, %{name: name}}}} ->
        %{
          url: @path <> "?v=" <> table().version,
          session: to_string(name),
          signed_in: Scope.user(assigns[:current_scope]) != nil
        }

      _ ->
        nil
    end
  end

  @doc "The path the table is served at."
  @spec path() :: String.t()
  def path, do: @path

  # A sign-in page is always a request, as if a controller page: only a
  # request carries the page the link was on (`UserAuth.store_return_to/2`).
  defp live_session(%{
         path: path,
         metadata: %{phoenix_live_view: {_view, _action, _opts, %{name: name}}}
       }) do
    unless GamendWeb.UserAuth.sign_in_page?(String.split(path, "/", trim: true)), do: name
  end

  defp live_session(_route), do: nil

  # A route's pipelines are only in its match, and its own path matches it. A
  # route that cannot be read this way (one scoped to a host) counts as
  # signed-in, so that a public page is what goes wrong, not a private one.
  defp signed_in_only?(router, path) do
    case Phoenix.Router.route_info(router, "GET", path, nil) do
      %{pipe_through: pipelines} -> :require_authenticated_user in pipelines
      :error -> true
    end
  end

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
