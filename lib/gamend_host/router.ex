defmodule GamendHost.Router do
  @moduledoc """
  Host-owned router for running application.

  Routes reference reusable controllers, LiveViews, and plugs from `gamend_web`.
  """

  use GamendWeb, :router

  import GamendWeb.UserAuth
  import GamendWeb.Router.Shared
  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router

  gamend_pipelines()

  @require_admin_on_mount GamendWeb.Router.Shared.require_admin_on_mount()
  @current_user_on_mount GamendWeb.Router.Shared.current_user_on_mount()

  scope "/content", GamendWeb do
    get "/:type/*path", HostContentAssetController, :show
  end

  gamend_static_page_routes()

  scope "/" do
    pipe_through :browser

    get "/sitemap.xml", GamendHost.SitemapController, :index
  end

  gamend_api_routes()
  gamend_support_routes()
  gamend_admin_live_routes(@require_admin_on_mount)

  # `HostPublicDocs` is this host's; the changelog, roadmap and blog pages are
  # core's now — see `GamendWeb.ContentPages`.
  gamend_current_user_routes(@current_user_on_mount,
    docs: HostPublicDocs,
    changelog: ChangelogLive,
    roadmap: RoadmapLive,
    blog: BlogLive,
    do: gamend_signed_in_routes()
  )

  gamend_oauth_routes()
  gamend_configured_page_fallback_routes()
end
