defmodule GamendWeb.SmallRouter do
  @moduledoc "A host router that leaves out everything `except:` can (`GamendWeb.LeftOutPagesTest`)."

  use GamendWeb, :router

  import GamendWeb.UserAuth
  import GamendWeb.Router.Shared
  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router

  gamend_pipelines()

  @authenticated GamendWeb.Router.Shared.require_authenticated_on_mount()
  @current_user GamendWeb.Router.Shared.current_user_on_mount()

  gamend_static_page_routes()
  gamend_api_routes(except: [:payments_catalog, :stripe_checkout, :report])
  gamend_support_routes()
  gamend_authenticated_live_routes(@authenticated, except: [:chat, :store, :groups, :friends])

  gamend_current_user_routes(@current_user,
    except: [:groups, :tournaments, :redeem, :report, :play]
  )

  gamend_oauth_routes()
  gamend_configured_page_fallback_routes()
end
