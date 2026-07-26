defmodule GameServerWeb.Router.Shared do
  @moduledoc """
  Route macros a host app mounts to get the server's HTTP surface.

  A host owns its own router; this module supplies the routes rather than
  imposing a router, so you choose which surfaces exist. Import it, declare the
  pipelines, then call the groups you want:

      defmodule MyGame.Router do
        use Phoenix.Router
        import GameServerWeb.Router.Shared

        game_server_pipelines()

        game_server_api_routes()
        game_server_public_api_routes()
        game_server_authenticated_live_routes()
        game_server_admin_live_routes(GameServerWeb.Router.Shared.require_admin_on_mount())
      end

  Leaving a group out removes those endpoints entirely — that is the supported
  way to ship a smaller surface, rather than deleting files from the dependency.

  ## Groups

  | Macro | Mounts |
  |---|---|
  | `game_server_pipelines/0` | The `:browser`, `:api`, `:api_auth` and `:api_admin` pipelines the rest expect. Call it first. |
  | `game_server_api_routes/0` | Auth, current user, lobbies, chat, KV, groups, parties, friends, notifications, quests, tournaments, matchmaking - the whole player-facing API. |
  | `game_server_public_api_routes/0` | Unauthenticated listings, each behind its own `LIST_*_ENABLED` flag. |
  | `game_server_api_auth_routes/0`, `game_server_oauth_routes/0` | Login, registration and the OAuth provider flows. |
  | `game_server_api_docs_routes/0` | The OpenAPI spec and Swagger UI at `/api/docs`. |
  | `game_server_authenticated_live_routes/0` | Player-facing LiveViews (lobbies, chat, quests, settings). |
  | `game_server_admin_live_routes/1` | The `/admin` console. Takes the `on_mount` hook from `require_admin_on_mount/0`. |
  | `game_server_admin_api_routes/0` | Admin HTTP mirrors of every console action. |
  | `game_server_static_page_routes/0`, `game_server_support_routes/0` | Host pages and support endpoints. |
  | `game_server_configured_page_fallback_routes/0` | Catch-all for theme-configured pages. Mount **last**. |

  The narrower macros (`game_server_chat_api_routes/0`,
  `game_server_quest_api_routes/0` and so on) are the pieces the aggregate
  macros above are built from; call them directly when you want one subsystem
  without its neighbours.
  """

  @browser_csp "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' wss:; font-src 'self' data:; frame-src 'self' blob:; frame-ancestors 'self'"
  @swagger_csp "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; img-src 'self' data: https:; connect-src 'self' wss:; font-src 'self' data:; frame-src 'self' blob:; frame-ancestors 'self'"
  # Oban Web serves its own JS/CSS from 'self' but its root layout emits a
  # nonce'd inline <script>, which the strict browser CSP would block. This
  # scoped policy (admin-only /admin/oban) allows it, mirroring :swagger_browser.
  @oban_csp "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss:; font-src 'self' data:; frame-ancestors 'self'"

  def browser_headers, do: %{"content-security-policy" => @browser_csp}
  def swagger_headers, do: %{"content-security-policy" => @swagger_csp}
  def oban_headers, do: %{"content-security-policy" => @oban_csp}

  def require_admin_on_mount do
    [
      {GameServerWeb.OnMount.Locale, :default},
      {GameServerWeb.UserAuth, :require_admin},
      {GameServerWeb.OnMount.Theme, :mount_theme},
      {GameServerWeb.OnMount.TrackConnection, :default}
    ]
  end

  def require_authenticated_on_mount do
    [
      {GameServerWeb.OnMount.Locale, :default},
      {GameServerWeb.UserAuth, :require_authenticated},
      {GameServerWeb.OnMount.Theme, :mount_theme},
      {GameServerWeb.OnMount.TrackConnection, :default}
    ]
  end

  def current_user_on_mount do
    [
      {GameServerWeb.OnMount.Locale, :default},
      {GameServerWeb.UserAuth, :mount_current_scope},
      {GameServerWeb.OnMount.Theme, :mount_theme},
      {GameServerWeb.OnMount.TrackConnection, :default}
    ]
  end

  defmacro game_server_pipelines do
    quote do
      alias GameServerWeb.Router.Shared, as: RouterShared

      pipeline :browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug :fetch_live_flash
        plug :put_root_layout, html: {GameServerWeb.Layouts, :root}
        plug :protect_from_forgery
        plug :put_secure_browser_headers, RouterShared.browser_headers()
        plug GameServerWeb.Plugs.ColorMode
        plug :fetch_current_scope_for_user
      end

      pipeline :api do
        plug :accepts, ["json"]
        plug OpenApiSpex.Plug.PutApiSpec, module: GameServerWeb.ApiSpec
      end

      pipeline :oauth_callback do
        plug :accepts, ["html", "json"]
        plug :fetch_session
        plug :fetch_live_flash
        plug :put_root_layout, html: {GameServerWeb.Layouts, :root}
        plug :put_secure_browser_headers, RouterShared.browser_headers()
        plug GameServerWeb.Plugs.ColorMode
        plug :fetch_current_scope_for_user
      end

      pipeline :api_auth do
        plug GameServerWeb.Auth.Pipeline
      end

      pipeline :api_optional_auth do
        plug GameServerWeb.Auth.OptionalPipeline
      end

      pipeline :api_admin do
        plug GameServerWeb.Plugs.RequireAdminApi
      end

      pipeline :mailbox_preview_enabled do
        plug GameServerWeb.Plugs.MailboxPreviewEnabled
      end

      pipeline :swagger_browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug :fetch_live_flash
        plug :put_root_layout, html: {GameServerWeb.Layouts, :root}
        plug :protect_from_forgery
        plug :put_secure_browser_headers, RouterShared.swagger_headers()
        plug :fetch_current_scope_for_user
      end

      pipeline :oban_browser do
        plug :accepts, ["html"]
        plug :fetch_session
        plug :fetch_live_flash
        plug :put_root_layout, html: {GameServerWeb.Layouts, :root}
        plug :protect_from_forgery
        plug :put_secure_browser_headers, RouterShared.oban_headers()
        plug :fetch_current_scope_for_user
      end

      pipeline :openapi_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :openapi
      end

      pipeline :list_users_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :list_users
      end

      pipeline :list_lobbies_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :list_lobbies
      end

      pipeline :list_groups_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :list_groups
      end

      pipeline :list_leaderboards_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :list_leaderboards
      end

      pipeline :list_quests_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :list_quests
      end

      pipeline :list_matchmaking_gate do
        plug GameServerWeb.Plugs.FeatureGate, feature: :list_matchmaking
      end

      pipeline :metrics_auth do
        plug GameServerWeb.Plugs.MetricsAuth
      end
    end
  end

  @doc """
  Core's static pages. `:home` swaps the controller behind `/` for a host's own
  (action `:home`); overriding by declaring the route first would compile to an
  unreachable clause.
  """
  defmacro game_server_static_page_routes(opts \\ []) do
    home = Keyword.get(opts, :home, quote(do: GameServerWeb.PageController))

    quote do
      # Its own scope, so a host controller is not resolved under GameServerWeb.
      scope "/" do
        pipe_through :browser

        get "/", unquote(home), :home
      end

      scope "/", GameServerWeb do
        pipe_through :browser

        get "/privacy", PageController, :privacy
        get "/data_deletion", PageController, :data_deletion
        get "/terms", PageController, :terms

        # The typed icon set as SVG, so `icon_url` can point at an icon we
        # already ship. Public and unauthenticated: it is static artwork.
        get "/icons/:name", IconController, :show
      end

      # Serve stored objects (local backend). With S3 the object URL points at the
      # bucket and this route is unused.
      scope "/", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through :browser

        get "/storage/*key", StorageController, :show
      end
    end
  end

  @doc """
  Every core API route. `:chat_update` swaps the controller behind
  `PATCH /api/v1/chat/messages/:id` for a host that moderates its own edits.
  """
  defmacro game_server_api_routes(opts \\ []) do
    chat_update = Keyword.get(opts, :chat_update, quote(do: ChatController))

    quote do
      game_server_api_docs_routes()
      game_server_public_api_routes()
      game_server_quest_api_routes()
      game_server_group_api_routes()
      game_server_kv_api_routes()
      game_server_account_lobby_api_routes()
      game_server_friend_notification_api_routes()
      game_server_group_mutation_api_routes()
      game_server_hook_leaderboard_party_api_routes()
      game_server_tournament_api_routes()
      game_server_matchmaking_api_routes()
      game_server_chat_api_routes(update: unquote(chat_update))
      game_server_admin_api_routes()
      game_server_api_auth_routes()
    end
  end

  defmacro game_server_api_docs_routes do
    quote do
      scope "/api" do
        pipe_through [:api, :openapi_gate]

        get "/openapi", OpenApiSpex.Plug.RenderSpec, []
      end

      scope "/api" do
        pipe_through [:swagger_browser, :openapi_gate]

        get "/docs", GameServerWeb.SwaggerController, :index
      end
    end
  end

  defmacro game_server_public_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through :api

        get "/health", HealthController, :index
        post "/login", SessionController, :create
        post "/login/device", SessionController, :create_device
        post "/refresh", SessionController, :refresh
        delete "/logout", SessionController, :delete
        get "/payments/catalog", PaymentController, :catalog
        post "/payments/webhooks/stripe", PaymentWebhookController, :stripe
        post "/payments/webhooks/google", PaymentWebhookController, :google
        post "/payments/webhooks/apple", PaymentWebhookController, :apple
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :list_users_gate]

        get "/users", UserController, :index
        get "/users/:id", UserController, :show
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :list_lobbies_gate]

        get "/lobbies", LobbyController, :index
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :list_groups_gate]

        get "/groups", GroupController, :index
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :list_leaderboards_gate]

        get "/leaderboards", LeaderboardController, :index
        post "/leaderboards/resolve", LeaderboardController, :resolve
        get "/leaderboards/:id", LeaderboardController, :show
        get "/leaderboards/:id/records", LeaderboardController, :records
        get "/leaderboards/:id/records/around/:user_id", LeaderboardController, :around
      end
    end
  end

  defmacro game_server_tournament_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api]

        get "/tournaments", TournamentController, :index
        get "/tournaments/:id/standings", TournamentController, :standings
        get "/tournaments/:id/entries", TournamentController, :entries
        get "/tournaments/:id/bracket", TournamentController, :bracket
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_optional_auth]

        get "/tournaments/:id", TournamentController, :show
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        post "/tournaments/:id/join", TournamentController, :join
        delete "/tournaments/:id/join", TournamentController, :leave
        get "/tournaments/:id/my_match", TournamentController, :my_match
      end
    end
  end

  defmacro game_server_matchmaking_api_routes do
    quote do
      # Mutations and the caller's own ticket are authenticated, not gated;
      # only the aggregate queue stats sit behind the listing gate.
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        post "/matchmaking/tickets", MatchmakingController, :create
        delete "/matchmaking/tickets", MatchmakingController, :delete
        get "/matchmaking/tickets/me", MatchmakingController, :me
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth, :list_matchmaking_gate]

        get "/matchmaking/stats", MatchmakingController, :stats
      end
    end
  end

  defmacro game_server_quest_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/me/quests", QuestController, :me
        post "/me/quests/:key/claim", QuestController, :claim
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_optional_auth, :list_quests_gate]

        get "/quests", QuestController, :index
        get "/quests/user/:user_id", QuestController, :user_quests
      end
    end
  end

  defmacro game_server_group_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/groups/invitations", GroupController, :invitations
        post "/groups/invitations/:invite_id/accept", GroupController, :accept_invite
        post "/groups/invitations/:invite_id/decline", GroupController, :decline_invite
        get "/groups/me", GroupController, :my_groups
        get "/groups/sent_invitations", GroupController, :sent_invitations
        delete "/groups/sent_invitations/:invite_id", GroupController, :cancel_invite
      end

      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :list_groups_gate]

        get "/groups/:id", GroupController, :show
        get "/groups/:id/members", GroupController, :members
      end
    end
  end

  defmacro game_server_kv_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/kv/:key", KvController, :show
      end
    end
  end

  defmacro game_server_account_lobby_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/me", MeController, :show
        delete "/me", MeController, :delete
        get "/lobbies/:id", LobbyController, :show
        post "/lobbies", LobbyController, :create
        post "/lobbies/quick_join", LobbyController, :quick_join
        patch "/lobbies", LobbyController, :update
        post "/lobbies/state", LobbyController, :set_state
        post "/lobbies/:id/join", LobbyController, :join
        post "/lobbies/leave", LobbyController, :leave
        post "/lobbies/kick", LobbyController, :kick
        post "/lobbies/ready_check", ReadyCheckController, :open
        delete "/lobbies/ready_check", ReadyCheckController, :cancel
        get "/me/ready_check", ReadyCheckController, :show
        post "/me/ready_check", ReadyCheckController, :respond
        patch "/me/password", MeController, :update_password
        patch "/me/display_name", MeController, :update_display_name
        patch "/me/username", MeController, :update_username
        post "/me/avatar/upload_url", MeController, :avatar_upload_url
        post "/me/avatar", MeController, :set_avatar
        put "/storage/upload", StorageController, :upload
        get "/me/wallet", EconomyController, :wallet
        get "/me/wallet/ledger", EconomyController, :ledger
        get "/me/inventory", EconomyController, :inventory
        get "/payments/entitlements", PaymentController, :entitlements
        post "/payments/checkout/stripe", PaymentController, :stripe_checkout
        post "/payments/checkout/steam", PaymentController, :steam_checkout
        post "/payments/steam/finalize", PaymentController, :steam_finalize
        post "/payments/validate/:provider", PaymentController, :validate
        delete "/me/providers/:provider", ProviderController, :unlink
        post "/me/device", ProviderController, :link_device
        delete "/me/device", ProviderController, :unlink_device
        post "/me/push_tokens", PushTokenController, :create
        get "/me/push_tokens", PushTokenController, :index
        delete "/me/push_tokens/:id", PushTokenController, :delete
      end
    end
  end

  defmacro game_server_friend_notification_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        post "/friends", FriendController, :create
        get "/me/friends", FriendController, :index
        get "/me/friend_requests", FriendController, :requests
        get "/me/blocked", FriendController, :blocked
        post "/friends/:id/accept", FriendController, :accept
        post "/friends/:id/reject", FriendController, :reject
        post "/friends/:id/block", FriendController, :block
        post "/friends/:id/unblock", FriendController, :unblock
        get "/me/blacklist", FriendController, :blacklist
        post "/users/:user_id/block", FriendController, :block_user
        post "/users/:user_id/unblock", FriendController, :unblock_user
        delete "/friends/:id", FriendController, :delete
        get "/notifications", NotificationController, :index
        post "/notifications", NotificationController, :create
        delete "/notifications", NotificationController, :delete
      end
    end
  end

  defmacro game_server_group_mutation_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        post "/groups", GroupController, :create
        patch "/groups/:id", GroupController, :update
        post "/groups/:id/join", GroupController, :join
        post "/groups/:id/leave", GroupController, :leave
        post "/groups/:id/kick", GroupController, :kick
        post "/groups/:id/promote", GroupController, :promote
        post "/groups/:id/demote", GroupController, :demote
        get "/groups/:id/join_requests", GroupController, :join_requests
        post "/groups/:id/join_requests/:request_id/approve", GroupController, :approve_request
        post "/groups/:id/join_requests/:request_id/reject", GroupController, :reject_request
        delete "/groups/:id/join_requests/:request_id", GroupController, :cancel_request
        post "/groups/:id/invite", GroupController, :invite
        post "/groups/:id/notify", GroupController, :notify_group
        post "/groups/:id/icon/upload_url", GroupController, :icon_upload_url
        post "/groups/:id/icon", GroupController, :set_icon
      end
    end
  end

  defmacro game_server_hook_leaderboard_party_api_routes do
    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/hooks", HookController, :index
        post "/hooks/call", HookController, :invoke
        get "/leaderboards/:id/records/me", LeaderboardController, :me
        get "/parties/me", PartyController, :show
        post "/parties", PartyController, :create
        patch "/parties", PartyController, :update
        post "/parties/leave", PartyController, :leave
        post "/parties/kick", PartyController, :kick
        post "/parties/invite", PartyController, :invite
        post "/parties/invite/cancel", PartyController, :cancel_party_invite
        post "/parties/invite/accept", PartyController, :accept_party_invite
        post "/parties/invite/decline", PartyController, :decline_party_invite
        get "/parties/invitations", PartyController, :list_invitations
        get "/parties/invitations/sent", PartyController, :list_sent_invitations
        post "/parties/create_lobby", PartyController, :create_lobby
        post "/parties/join_lobby/:id", PartyController, :join_lobby
        post "/parties/ready_check", ReadyCheckController, :open_party
        delete "/parties/ready_check", ReadyCheckController, :cancel_party
      end
    end
  end

  defmacro game_server_chat_api_routes(opts \\ []) do
    update = Keyword.get(opts, :update, quote(do: ChatController))

    quote do
      scope "/api/v1", GameServerWeb.Api.V1, as: :api_v1 do
        pipe_through [:api, :api_auth]

        get "/chat/messages", ChatController, :index
        get "/chat/messages/:id", ChatController, :show
        post "/chat/messages", ChatController, :send
        patch "/chat/messages/:id", unquote(update), :update
        delete "/chat/messages/:id", ChatController, :delete
        post "/chat/read", ChatController, :mark_read
        get "/chat/unread", ChatController, :unread
      end
    end
  end

  defmacro game_server_admin_api_routes do
    quote do
      game_server_admin_kv_leaderboard_api_routes()
      game_server_admin_management_api_routes()
      game_server_admin_chat_quest_api_routes()
    end
  end

  defmacro game_server_admin_kv_leaderboard_api_routes do
    quote do
      scope "/api/v1/admin", GameServerWeb.Api.V1.Admin, as: :api_v1_admin do
        pipe_through [:api, :api_auth, :api_admin]

        get "/kv/entries", KvEntryController, :index
        post "/kv/entries", KvEntryController, :create
        patch "/kv/entries/:id", KvEntryController, :update
        delete "/kv/entries/:id", KvEntryController, :delete
        put "/kv", KvController, :upsert
        delete "/kv", KvController, :delete
        post "/leaderboards", LeaderboardController, :create
        patch "/leaderboards/:id", LeaderboardController, :update
        post "/leaderboards/:id/end", LeaderboardController, :end_leaderboard
        post "/leaderboards/:id/icon/upload_url", LeaderboardController, :icon_upload_url
        post "/leaderboards/:id/icon", LeaderboardController, :set_icon
        delete "/leaderboards/:id", LeaderboardController, :delete
        post "/leaderboards/:id/records", LeaderboardRecordController, :create
        patch "/leaderboards/:id/records/:record_id", LeaderboardRecordController, :update
        delete "/leaderboards/:id/records/:record_id", LeaderboardRecordController, :delete

        delete "/leaderboards/:id/records/user/:user_id",
               LeaderboardRecordController,
               :delete_user

        post "/tournaments", TournamentController, :create
        patch "/tournaments/:id", TournamentController, :update
        delete "/tournaments/:id", TournamentController, :delete
        post "/tournaments/:id/icon/upload_url", TournamentController, :icon_upload_url
        post "/tournaments/:id/icon", TournamentController, :set_icon
        post "/tournaments/:id/cancel", TournamentController, :cancel
        post "/tournaments/:id/reopen", TournamentController, :reopen
        post "/tournaments/:id/draw", TournamentController, :draw
        post "/tournaments/:id/finish", TournamentController, :finish
        post "/tournaments/:id/matches/:match_id/resolve", TournamentController, :resolve_match

        get "/matchmaking/tickets", MatchmakingController, :index
        delete "/matchmaking/tickets/:id", MatchmakingController, :delete
        get "/matchmaking/stats", MatchmakingController, :stats
        get "/ready_checks", ReadyCheckController, :index
        delete "/ready_checks/:id", ReadyCheckController, :delete
        get "/ready_checks/stats", ReadyCheckController, :stats
      end
    end
  end

  defmacro game_server_admin_management_api_routes do
    quote do
      scope "/api/v1/admin", GameServerWeb.Api.V1.Admin, as: :api_v1_admin do
        pipe_through [:api, :api_auth, :api_admin]

        get "/lobbies", LobbyController, :index
        patch "/lobbies/:id", LobbyController, :update
        delete "/lobbies/:id", LobbyController, :delete
        patch "/users/:id", UserController, :update
        delete "/users/:id", UserController, :delete
        get "/notifications", NotificationController, :index
        post "/notifications", NotificationController, :create
        delete "/notifications/:id", NotificationController, :delete
        get "/push/tokens", PushController, :index
        delete "/push/tokens/:id", PushController, :delete
        post "/push/send", PushController, :send
        get "/groups", GroupController, :index
        patch "/groups/:id", GroupController, :update
        delete "/groups/:id", GroupController, :delete
        get "/sessions", SessionController, :index
        delete "/sessions/:id", SessionController, :delete
        delete "/users/:id/sessions", SessionController, :delete_user_sessions
        get "/storage", StorageController, :index
        delete "/storage", StorageController, :delete
        put "/storage/object", StorageController, :upload
        get "/storage/object", StorageController, :download
        get "/economy/wallets", EconomyController, :wallets
        get "/economy/ledger", EconomyController, :ledger
        post "/economy/grant", EconomyController, :grant
        post "/economy/spend", EconomyController, :spend
        get "/economy/items", EconomyController, :items
        post "/economy/grant_item", EconomyController, :grant_item
        post "/economy/consume_item", EconomyController, :consume_item
        get "/retention", RetentionController, :show
        post "/retention/run", RetentionController, :run
      end
    end
  end

  defmacro game_server_admin_chat_quest_api_routes do
    quote do
      scope "/api/v1/admin", GameServerWeb.Api.V1.Admin, as: :api_v1_admin do
        pipe_through [:api, :api_auth, :api_admin]

        get "/chat", ChatController, :index
        delete "/chat/:id", ChatController, :delete
        delete "/chat/conversation", ChatController, :delete_conversation
        get "/quests", QuestController, :index
        post "/quests", QuestController, :create
        patch "/quests/:id", QuestController, :update
        delete "/quests/:id", QuestController, :delete
        post "/quests/:id/icon/upload_url", QuestController, :icon_upload_url
        post "/quests/:id/icon", QuestController, :set_icon
        get "/quests/progress", QuestController, :progress
        post "/quests/grant", QuestController, :grant
        post "/quests/reset", QuestController, :reset
        post "/quests/claim", QuestController, :claim
        get "/quests/:key/funnel", QuestController, :funnel
      end
    end
  end

  defmacro game_server_api_auth_routes do
    quote do
      scope "/api/v1/auth", GameServerWeb do
        pipe_through :api

        get "/:provider", AuthController, :api_request
        post "/:provider/callback", AuthController, :api_callback
        post "/apple/ios/callback", AuthController, :api_apple_ios_callback
        post "/google/id_token", AuthController, :api_google_id_token
        get "/session/:session_id", AuthController, :api_session_status
      end
    end
  end

  defmacro game_server_support_routes do
    quote do
      scope "/" do
        pipe_through [:browser, :mailbox_preview_enabled]

        forward "/dev/mailbox", Plug.Swoosh.MailboxPreview
      end

      scope "/" do
        pipe_through [:browser, :require_admin_user]

        live_dashboard "/admin/dashboard", metrics: GameServerWeb.Telemetry
      end

      scope "/" do
        # Oban Web needs its own (scoped) CSP for its inline script. Gated on the
        # socket too, not just the HTTP request — our on_mount runs before Oban
        # Web's own Authentication.
        pipe_through [:oban_browser, :require_admin_user]

        oban_dashboard("/admin/oban", on_mount: [{GameServerWeb.UserAuth, :require_admin}])
      end

      scope "/" do
        pipe_through [:metrics_auth]

        get "/metrics", PromEx.Plug, prom_ex_module: GameServerWeb.PromEx
      end
    end
  end

  @doc """
  Core's admin LiveView routes, optionally extended with host-specific ones.

  The `do` block is spliced into the same `live_session`, so host routes get the
  admin pipeline and `on_mount` chain without the host restating them:

      game_server_admin_live_routes @require_admin_on_mount do
        live "/admin/my_thing", MyThingLive, :index
      end

  It exists so a host that needs one extra admin page does not fork the whole
  list to get it. A fork looks harmless and then silently rots — every core
  admin page added afterwards is missing from that host, with no error, just a
  404 nobody connects to the change that caused it.
  """
  defmacro game_server_admin_live_routes(on_mount, opts \\ []) do
    host_routes = Keyword.get(opts, :do)

    quote do
      scope "/", GameServerWeb do
        pipe_through [:browser, :require_admin_user]

        live_session :require_admin,
          on_mount: unquote(on_mount) do
          unquote(host_routes)

          live "/admin", AdminLive.Index, :index
          live "/admin/config", AdminLive.Config, :index
          live "/admin/settings", AdminLive.Settings, :index
          live "/admin/kv", AdminLive.KV, :index
          live "/admin/lobbies", AdminLive.Lobbies, :index
          live "/admin/lobbies/live", LobbyLive.Index, :index
          live "/admin/leaderboards", AdminLive.Leaderboards, :index
          live "/admin/tournaments", AdminLive.Tournaments, :index
          live "/admin/matchmaking", AdminLive.Matchmaking, :index
          live "/admin/users", AdminLive.Users, :index
          live "/admin/sessions", AdminLive.Sessions, :index
          live "/admin/notifications", AdminLive.Notifications, :index
          live "/admin/push", AdminLive.Push, :index
          live "/admin/groups", AdminLive.Groups, :index
          live "/admin/parties", AdminLive.Parties, :index
          live "/admin/blacklist", AdminLive.Blacklist, :index
          live "/admin/chat", AdminLive.Chat, :index
          live "/admin/quests", AdminLive.Quests, :index
          live "/admin/payments", AdminLive.Payments, :index
          live "/admin/translations", AdminLive.Translations, :index
          live "/admin/connections", AdminLive.Connections, :index
          live "/admin/rate_limiting", AdminLive.RateLimiting, :index
          live "/admin/logs", AdminLive.Logs, :index
          live "/admin/lobby_snapshots", AdminLive.LobbySnapshots, :index
          live "/admin/geo", AdminLive.Geo, :index
          live "/admin/system", AdminLive.System, :index
          live "/admin/runtime", AdminLive.Runtime, :index
          live "/admin/storage", AdminLive.Storage, :index
          live "/admin/economy", AdminLive.Economy, :index
        end
      end
    end
  end

  @doc """
  Core's authenticated LiveView routes, extendable the same way as the admin ones.

  `:do` splices host routes into the same `live_session`; `:chat` swaps the chat
  LiveView for a host's own. The session name is fixed, so a host cannot declare
  a second `live_session :require_authenticated_user` of its own — it extends
  this one or forks the lot.
  """
  defmacro game_server_authenticated_live_routes(on_mount, opts \\ []) do
    host_routes = Keyword.get(opts, :do)
    chat = Keyword.get(opts, :chat, quote(do: ChatLive))

    quote do
      scope "/", GameServerWeb do
        pipe_through [:browser, :require_authenticated_user]

        live_session :require_authenticated_user,
          on_mount: unquote(on_mount) do
          unquote(host_routes)

          live "/users/settings", UserLive.Settings, :edit
          live "/users/settings/confirm_email/:token", UserLive.Settings, :confirm_email
          live "/store", StoreLive.Index, :index
          live "/store/success", StoreLive.Index, :success
          live "/store/cancel", StoreLive.Index, :cancel
          live "/notifications", NotificationsLive, :index
          live "/chat", unquote(chat), :index
        end

        post "/users/update_password", UserSessionController, :update_password
        get "/payments/downloads/:id", PaymentDownloadController, :show
      end
    end
  end

  @doc """
  Core's public LiveView routes, extendable with host-specific ones via `:do`.

  Same reasoning as the admin and authenticated variants: `live_session
  :current_user` can only be declared once, so a host adding one public page
  extends this rather than restating core's list.
  """
  defmacro game_server_current_user_routes(on_mount, opts \\ []) do
    host_routes = Keyword.get(opts, :do)
    docs = Keyword.get(opts, :docs)
    changelog = Keyword.get(opts, :changelog)
    roadmap = Keyword.get(opts, :roadmap)
    blog = Keyword.get(opts, :blog)

    docs_route =
      if docs do
        quote do
          live "/docs/setup", unquote(docs), :index
        end
      end

    # A host that renders its own changelog/roadmap/blog omits these; the routes
    # are not emitted at all rather than being shadowed by a host route.
    changelog_route =
      if changelog do
        quote(do: live("/changelog", unquote(changelog), :index))
      end

    roadmap_route =
      if roadmap do
        quote(do: live("/roadmap", unquote(roadmap), :index))
      end

    blog_routes =
      if blog do
        quote do
          live "/blog", unquote(blog), :index
          live "/blog/:slug", unquote(blog), :show
        end
      end

    quote do
      scope "/", GameServerWeb do
        pipe_through [:browser]

        live_session :current_user,
          on_mount: unquote(on_mount) do
          unquote(host_routes)

          live "/users/register", UserLive.Registration, :new
          live "/groups", GroupsLive, :index
          live "/groups/:id", GroupsLive, :show
          live "/quests", QuestsLive, :index
          live "/tournaments", TournamentsLive, :index
          # Slug-first for SEO; older editions get a stable 1-based number.
          # A UUID still resolves in the :slug position, so old links keep working.
          live "/tournaments/:slug", TournamentsLive, :show
          live "/tournaments/:slug/brackets/:index", TournamentsLive, :bracket
          live "/tournaments/:slug/:edition", TournamentsLive, :show
          live "/tournaments/:slug/:edition/brackets/:index", TournamentsLive, :bracket
          live "/leaderboards", LeaderboardsLive, :index
          live "/leaderboards/:slug/:id", LeaderboardsLive, :show
          live "/leaderboards/:slug", LeaderboardsLive, :show_active
          live "/users/log_in", UserLive.Login, :new
          live "/users/log_in/:token", UserLive.Confirmation, :new
          get "/users/confirm/:token", UserSessionController, :confirm
          unquote(docs_route)
          unquote(changelog_route)
          unquote(roadmap_route)
          unquote(blog_routes)
          live "/auth/success", AuthSuccessLive, :index
          live "/play", PlayLive, :index
        end

        post "/users/log_in", UserSessionController, :create
        delete "/users/log_out", UserSessionController, :delete
      end
    end
  end

  defmacro game_server_oauth_routes do
    quote do
      scope "/auth", GameServerWeb do
        pipe_through :oauth_callback

        post "/:provider/callback", AuthController, :callback
        get "/steam/callback", AuthController, :steam_callback
      end

      scope "/auth", GameServerWeb do
        pipe_through :browser

        get "/:provider", AuthController, :request
        get "/:provider/callback", AuthController, :callback
      end
    end
  end

  defmacro game_server_configured_page_fallback_routes do
    quote do
      scope "/", GameServerWeb do
        pipe_through :browser

        get "/*path", PageController, :configured_page
      end
    end
  end
end
