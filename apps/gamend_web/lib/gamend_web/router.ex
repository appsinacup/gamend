defmodule GamendWeb.Router do
  use GamendWeb, :router

  import GamendWeb.UserAuth
  import GamendWeb.Router.Shared
  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router

  gamend_pipelines()

  @require_admin_on_mount GamendWeb.Router.Shared.require_admin_on_mount()
  @current_user_on_mount GamendWeb.Router.Shared.current_user_on_mount()

  gamend_static_page_routes()
  gamend_api_routes()
  gamend_support_routes()
  gamend_admin_live_routes(@require_admin_on_mount)

  gamend_current_user_routes(@current_user_on_mount,
    changelog: ChangelogLive,
    roadmap: RoadmapLive,
    blog: BlogLive,
    # The groups page at a path of its own, as a host whose nav links to its
    # groups mounts it (Forge's and Gamend Cloud's, at this same path).
    do: gamend_signed_in_routes(groups: "/users/groups")
  )

  gamend_github_routes()
  gamend_oauth_routes()
  gamend_configured_page_fallback_routes()
end
