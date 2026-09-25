defmodule GamendWeb.AuthController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  # Before Ueberauth, so a disabled Steam is 404'd ahead of its request phase.
  plug :ensure_provider_enabled

  # Only use Ueberauth for Steam (OpenID), other providers use custom implementation
  plug Ueberauth, only: [:request, :callback], providers: [:steam]

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.OAuth.Providers
  alias Gamend.OAuthSessions
  alias GamendWeb.Auth.OAuthExchange
  alias GamendWeb.Auth.Tokens
  alias GamendWeb.Schemas
  alias GamendWeb.UserAuth

  @browser_state_prefix "browser:"

  @provider_atom %{
    "discord" => :discord,
    "google" => :google,
    "apple" => :apple,
    "facebook" => :facebook,
    "github" => :github,
    "steam" => :steam
  }

  # 404s every provider-specific action for a provider that is disabled or
  # unknown, so a switched-off provider looks like it does not exist. Actions
  # without a :provider param derive it from what they verify.
  defp ensure_provider_enabled(conn, _opts) do
    provider =
      case Phoenix.Controller.action_name(conn) do
        :api_apple_ios_callback -> :apple
        :api_google_id_token -> :google
        _action -> @provider_atom[conn.params["provider"]]
      end

    cond do
      is_nil(conn.params["provider"]) and provider == nil -> conn
      Providers.enabled?(provider) -> conn
      true -> raise GamendWeb.NotFoundError
    end
  end

  # ── Browser OAuth CSRF helpers ──────────────────────────────────────────

  # Generate a random state nonce and persist it server-side.
  #
  # Do not validate browser OAuth with Plug session cookies here. Apple uses
  # response_mode=form_post, so its callback is a cross-site POST. With
  # SameSite=Lax cookies, browsers can omit the session cookie on that POST,
  # which makes session-backed state validation fail even when Apple auth
  # succeeded. Server-side OAuthSession state is the source of truth.
  defp put_oauth_state(conn, provider) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    state = @browser_state_prefix <> nonce
    data = browser_oauth_state_data(conn)

    {:ok, _session} =
      OAuthSessions.create_session(state, %{
        provider: provider,
        status: "pending",
        data: data
      })

    {conn, state}
  end

  defp browser_oauth_state_data(%{assigns: %{current_scope: %Scope{user_id: user_id}}}) do
    %{browser: true, link_user_id: user_id}
  end

  defp browser_oauth_state_data(_conn), do: %{browser: true}

  # Classify an OAuth callback as :browser, :api, or :csrf_error.
  #
  # Returns:
  #   {:browser, conn}           — validated browser state nonce
  #   {:api, session_id}         — valid OAuthSession for API polling flow
  #   {:csrf_error, conn}        — browser nonce mismatch or missing
  defp dispatch_oauth_state(conn, state) do
    case state do
      nil ->
        # No state at all — could be a very old client. Reject for safety.
        {:csrf_error, conn}

      @browser_state_prefix <> _nonce = browser_state ->
        dispatch_browser_oauth_state(conn, browser_state)

      session_id ->
        # Not a browser state — must be an API OAuthSession that is still
        # pending, was started for this provider, and has not aged out.
        #
        # Accepting any row in any status let a started flow stay redeemable
        # indefinitely: an attacker could begin the API flow, send the
        # authorization URL to someone else, and collect that person's tokens
        # from their own session id long afterwards.
        case OAuthSessions.get_pending_session(session_id, provider_of(conn)) do
          nil -> {:csrf_error, conn}
          _session -> {:api, session_id}
        end
    end
  end

  # The provider named in the callback path, used to reject a state issued for
  # a different one.
  defp provider_of(%{params: %{"provider" => provider}}) when is_binary(provider), do: provider
  defp provider_of(_conn), do: nil

  defp dispatch_browser_oauth_state(conn, browser_state) do
    case OAuthSessions.get_pending_session(browser_state, provider_of(conn)) do
      %{} = session ->
        # Consume state once. Do not fall back to Plug session cookies for browser
        # OAuth: Apple form_post callbacks can legitimately arrive without them.
        _ = OAuthSessions.update_session(browser_state, %{status: "completed"})

        conn = maybe_restore_browser_link_scope(conn, session)

        {:browser, conn}

      nil ->
        # Not acceptable — but distinguish a state that was already redeemed
        # from one that never existed. Pressing back after signing in,
        # refreshing the callback, or a link prefetcher touching the URL all
        # produce a redeemed state, and single-use state working exactly as
        # designed is not a CSRF failure; reporting it as one buries the real
        # thing. An expired or provider-mismatched state is a genuine reject.
        case OAuthSessions.get_session(browser_state) do
          %{status: status} when status != "pending" -> {:state_replayed, conn}
          _ -> {:csrf_error, conn}
        end
    end
  end

  defp maybe_restore_browser_link_scope(conn, %{data: %{} = data}) do
    case Map.get(data, "link_user_id") || Map.get(data, :link_user_id) do
      user_id when is_binary(user_id) ->
        case Accounts.get_user(user_id) do
          %User{} = user -> Plug.Conn.assign(conn, :current_scope, Scope.for_user(user))
          _ -> conn
        end

      _ ->
        conn
    end
  end

  # The API polling flow's callback: the provider sent the player back with
  # `state` = an OAuth session id. A session started by
  # `POST /api/v1/me/providers/:provider/authorize` carries `link_user_id` and
  # links; one started by `GET /api/v1/auth/:provider` signs in. What the
  # client started decides, never whether a token happened to be sent.
  defp handle_session_oauth_callback(conn, session_id, user_params, provider) do
    config = OAuthExchange.provider!(provider)
    session = OAuthSessions.get_session(session_id)

    outcome =
      case session && (session.data["link_user_id"] || session.data[:link_user_id]) do
        link_user_id when is_binary(link_user_id) ->
          link_session_outcome(link_user_id, user_params, provider, config)

        _ ->
          sign_in_session_outcome(user_params, config)
      end

    OAuthSessions.create_session(session_id, outcome)
    redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
  end

  defp link_session_outcome(link_user_id, user_params, provider, config) do
    case Accounts.get_user(link_user_id) do
      %User{} = user ->
        case Accounts.link_account(user, user_params, config.id_field, config.changeset) do
          {:ok, _updated_user} ->
            %{status: "completed", data: %{link_user_id: link_user_id, provider: provider}}

          {:error, {:conflict, _other_user}} ->
            session_error(
              "provider_already_linked",
              "This provider is already linked to another account",
              %{link_user_id: link_user_id, provider: provider}
            )

          {:error, _changeset} ->
            session_error("link_failed", "The provider could not be linked", %{
              link_user_id: link_user_id,
              provider: provider
            })
        end

      nil ->
        session_error("user_not_found", "The user to link to was not found", %{
          link_user_id: link_user_id,
          provider: provider
        })
    end
  end

  defp sign_in_session_outcome(user_params, config) do
    case config.finder.(user_params) do
      {:ok, user} ->
        case Tokens.refusal(user) do
          nil -> %{status: "completed", data: Tokens.sign_in(user)}
          {_status, code, message} -> session_error(code, message)
        end

      {:error, _changeset} ->
        session_error("sign_in_failed", "The account could not be created")
    end
  end

  defp session_error(code, message, data \\ %{}) do
    %{status: "error", data: Map.merge(data, %{error: code, message: message})}
  end

  # A provider sign-in over the API: find or create the account, answer the
  # same `Session` as email and device login.
  defp sign_in_api(conn, provider, user_params) do
    config = OAuthExchange.provider!(provider)

    case config.finder.(user_params) do
      {:ok, user} ->
        case Tokens.refusal(user) do
          nil -> reply_data(conn, Tokens.sign_in(user))
          {status, code, message} -> reply_error(conn, status, code, message)
        end

      {:error, changeset} ->
        unprocessable(conn, changeset)
    end
  end

  # An already-redeemed callback. The reader is almost always signed in
  # already — they pressed back — so this is worth one info line, not an error
  # and not a failure flash claiming their sign-in did not work.
  defp browser_oauth_replay_redirect(conn, provider) do
    require Logger

    Logger.info("#{String.capitalize(provider)} OAuth callback replayed (state already redeemed)")

    redirect(conn, to: ~p"/users/log_in")
  end

  # Show a helpful dev-mode flash for browser flows when exchanges fail
  defp browser_oauth_error_redirect(conn, provider, error) do
    # Log the error at controller level as well
    require Logger

    Logger.error(
      "#{String.capitalize(provider)} OAuth exchange failed (controller): #{inspect(error)}"
    )

    msg =
      if dev_env?() do
        "Failed to authenticate with #{String.capitalize(provider)}: #{inspect(error)}"
      else
        "Failed to authenticate with #{String.capitalize(provider)}."
      end

    conn
    |> put_flash(:error, msg)
    |> redirect(to: ~p"/users/log_in")
  end

  defp handle_browser_oauth_callback(conn, provider, user_params) do
    config = OAuthExchange.provider!(provider)

    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = current_user ->
        case Accounts.link_account(
               current_user,
               user_params,
               config.id_field,
               config.changeset
             ) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, gettext("Success."))
            |> redirect(to: ~p"/users/settings")

          {:error, {:conflict, other_user}} ->
            require Logger
            Logger.warning("#{config.label} already linked to another user id=#{other_user.id}")

            # The conflict is recorded in the session, not in the URL.
            #
            # It used to travel as `?conflict_user_id=`, and the settings page
            # rendered a delete button straight from that parameter — so any
            # signed-in user could name any account and delete it, provided it
            # had no password (which is every device and OAuth-only account).
            # Only this branch has actually proven the caller controls the
            # provider identity the other account claims, so only this branch
            # may authorise anything.
            conn
            |> put_flash(:error, gettext("Failed"))
            |> put_session(:oauth_link_conflict, %{
              "provider" => provider,
              "user_id" => other_user.id,
              "at" => System.system_time(:second)
            })
            |> redirect(to: ~p"/users/settings")

          {:error, changeset} ->
            require Logger
            Logger.error("Failed to link #{config.label}: #{inspect(changeset.errors)}")

            conn
            |> put_flash(:error, gettext("Failed"))
            |> redirect(to: ~p"/users/settings")
        end

      _ ->
        case config.finder.(user_params) do
          {:ok, user} ->
            if Accounts.user_activated?(user) do
              conn
              |> put_flash(:info, gettext("Success."))
              |> UserAuth.log_in_user(user)
            else
              conn
              |> put_flash(
                :error,
                gettext("Your account is pending activation.")
              )
              |> redirect(to: ~p"/users/log_in")
            end

          {:error, changeset} ->
            require Logger

            Logger.error(
              "Failed to create user from #{config.label}: #{inspect(changeset.errors)}"
            )

            conn
            |> put_flash(:error, gettext("Failed"))
            |> redirect(to: ~p"/users/log_in")
        end
    end
  end

  defp dev_env? do
    Application.get_env(:gamend_web, :environment, :prod) == :dev
  end

  # Browser OAuth request - redirects to provider
  operation(:request,
    operation_id: "oauth_request_browser",
    summary: "Browser OAuth request",
    description: "Initiate a browser OAuth flow and redirect the user to the provider",
    tags: ["Authentication"],
    parameters: [
      provider: [
        in: :path,
        name: "provider",
        schema: %OpenApiSpex.Schema{
          type: :string,
          enum: ["discord", "apple", "google", "facebook", "github", "steam"]
        },
        required: true
      ]
    ],
    responses: [
      found: {"Redirect to provider", "text/html", %OpenApiSpex.Schema{type: :string}}
    ]
  )

  def request(conn, %{"provider" => "discord"}) do
    client_id = Gamend.Settings.get(Gamend.OAuth.Providers, :discord_client_id)

    base = GamendWeb.endpoint().url()
    redirect_uri = "#{base}/auth/discord/callback"
    scope = "identify email"
    {conn, state} = put_oauth_state(conn, "discord")

    url =
      "https://discord.com/oauth2/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  # steam_callback helper is defined with the other callbacks below

  # Steam callback handlers live alongside other provider callbacks below

  def request(conn, %{"provider" => "google"}) do
    client_id = Gamend.Settings.get(Gamend.OAuth.Providers, :google_client_id)

    base = GamendWeb.endpoint().url()
    redirect_uri = "#{base}/auth/google/callback"
    scope = "email profile"
    {conn, state} = put_oauth_state(conn, "google")

    url =
      "https://accounts.google.com/o/oauth2/v2/auth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&access_type=offline&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  def request(conn, %{"provider" => "facebook"}) do
    client_id = Gamend.Settings.get(Gamend.OAuth.Providers, :facebook_client_id)

    base = GamendWeb.endpoint().url()
    redirect_uri = "#{base}/auth/facebook/callback"
    scope = "email"
    {conn, state} = put_oauth_state(conn, "facebook")

    url =
      "https://www.facebook.com/v18.0/dialog/oauth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  # No scope: a GitHub App ignores it, its permissions are set on the App.
  def request(conn, %{"provider" => "github"}) do
    client_id = Gamend.Settings.get(Gamend.OAuth.Providers, :github_client_id)

    base = GamendWeb.endpoint().url()
    redirect_uri = "#{base}/auth/github/callback"
    {conn, state} = put_oauth_state(conn, "github")

    url =
      "https://github.com/login/oauth/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  def request(conn, %{"provider" => "apple"}) do
    cfg = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth, [])
    client_id = Gamend.Settings.get(Gamend.OAuth.Providers, :apple_client_id)

    base = GamendWeb.endpoint().url()
    redirect_uri = cfg[:redirect_uri] || "#{base}/auth/apple/callback"
    scope = "name email"
    {conn, state} = put_oauth_state(conn, "apple")

    url =
      "https://appleid.apple.com/auth/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&response_mode=form_post&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  # helper route used for Steam callback routing - delegates into the
  # unified `callback/2` handler by injecting the `provider` param.
  operation(:steam_callback,
    operation_id: "oauth_callback_steam",
    summary: "Steam callback (browser OpenID helper)",
    description:
      "Helper route used for Steam OpenID callbacks. Delegates to `callback/2` with provider=steam.",
    tags: ["Authentication"],
    parameters: [
      state: [
        in: :query,
        name: "state",
        schema: %OpenApiSpex.Schema{type: :string},
        required: false
      ]
    ],
    responses: [
      found: {"Redirect or success page", "text/html", %OpenApiSpex.Schema{type: :string}},
      bad_request: {"Bad request", "text/html", %OpenApiSpex.Schema{type: :string}}
    ]
  )

  def steam_callback(conn, params) do
    callback(conn, Map.put(params, "provider", "steam"))
  end

  operation(:callback,
    operation_id: "oauth_callback_browser",
    summary: "Browser OAuth callback",
    description:
      "Handles provider callback for browser OAuth flows (redirects or shows messages)",
    tags: ["Authentication"],
    parameters: [
      provider: [
        in: :path,
        name: "provider",
        schema: %OpenApiSpex.Schema{type: :string},
        required: true
      ],
      code: [
        in: :query,
        name: "code",
        schema: %OpenApiSpex.Schema{type: :string},
        required: false
      ],
      state: [
        in: :query,
        name: "state",
        schema: %OpenApiSpex.Schema{type: :string},
        required: false
      ]
    ],
    responses: [
      found: {"Redirect or success page", "text/html", %OpenApiSpex.Schema{type: :string}},
      bad_request: {"Bad request", "text/html", %OpenApiSpex.Schema{type: :string}}
    ]
  )

  # Unified OAuth callback - handles both browser and API flows
  # API flows include a 'state' parameter with session_id
  # Browser flows don't have state
  def callback(conn, %{"provider" => provider, "code" => code} = params)
      when provider in ["discord", "google", "facebook", "github", "apple"] do
    case OAuthExchange.exchange_code(provider, code) do
      {:ok, user_params} ->
        user_params =
          if provider == "apple",
            do:
              OAuthExchange.put_apple_name(
                user_params,
                OAuthExchange.apple_web_name(params["user"])
              ),
            else: user_params

        handle_oauth_state_success(conn, provider, user_params, params["state"])

      {:error, error} ->
        handle_oauth_state_error(conn, provider, error, params["state"])
    end
  end

  def callback(
        %Plug.Conn{assigns: %{ueberauth_auth: auth}} = conn,
        %{"provider" => "steam"} = params
      ) do
    uid = to_string(auth.uid)
    info = auth.info || %{}
    extra = Map.get(auth, :extra) || %{}
    raw_info = Map.get(extra, :raw_info) || %{}
    raw_user = Map.get(raw_info, :user) || %{}

    display_name =
      Map.get(info, :name) ||
        Map.get(info, :nickname) ||
        Map.get(raw_user, :personaname) ||
        Map.get(raw_user, :realname)

    urls = Map.get(info, :urls, %{})
    profile_url = Map.get(urls, :profile) || Map.get(info, :image)

    user_params = %{
      steam_id: uid,
      display_name: display_name,
      profile_url: profile_url
    }

    case params["state"] do
      nil ->
        handle_browser_oauth_callback(conn, "steam", user_params)

      session_id ->
        # Only a pending Steam session, as `dispatch_oauth_state/2` requires
        # for the other providers: a finished one redeemed again would hand
        # this player's tokens to whoever started it.
        case OAuthSessions.get_pending_session(session_id, "steam") do
          nil ->
            handle_browser_oauth_callback(conn, "steam", user_params)

          _ ->
            handle_session_oauth_callback(conn, session_id, user_params, "steam")
        end
    end
  end

  def callback(
        %Plug.Conn{assigns: %{ueberauth_failure: failure}} = conn,
        %{"provider" => "steam"} = params
      ) do
    case params["state"] do
      nil ->
        browser_oauth_error_redirect(conn, "steam", failure)

      session_id ->
        case OAuthSessions.get_session(session_id) do
          nil ->
            browser_oauth_error_redirect(conn, "steam", failure)

          _ ->
            Gamend.OAuthSessions.create_session(
              session_id,
              session_error("authentication_failed", "The provider did not sign the player in")
            )

            redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
        end
    end
  end

  # Catch-all for missing code or unsupported providers. A warning, not an
  # error: this is a reloaded or bookmarked callback URL, or a crawler
  # following one — the user's dead end, not a fault here, and it must not
  # count as one on the admin Logs page.
  def callback(conn, params) do
    require Logger

    Logger.warning(
      "OAuth callback with invalid params. Provider: #{params["provider"]}, Params: #{inspect(params)}"
    )

    conn
    |> put_flash(:error, gettext("Failed"))
    |> redirect(to: ~p"/users/log_in")
  end

  defp handle_oauth_state_success(conn, provider, user_params, state) do
    case dispatch_oauth_state(conn, state) do
      {:browser, conn} ->
        handle_browser_oauth_callback(conn, provider, user_params)

      {:api, session_id} ->
        handle_session_oauth_callback(conn, session_id, user_params, provider)

      {:state_replayed, conn} ->
        browser_oauth_replay_redirect(conn, provider)

      {:csrf_error, conn} ->
        browser_oauth_error_redirect(conn, provider, "csrf_validation_failed")
    end
  end

  defp handle_oauth_state_error(conn, provider, error, state) do
    case dispatch_oauth_state(conn, state) do
      {:browser, conn} ->
        browser_oauth_error_redirect(conn, provider, error)

      {:api, session_id} ->
        Gamend.OAuthSessions.create_session(
          session_id,
          session_error("authentication_failed", "The provider did not sign the player in")
        )

        redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")

      {:state_replayed, conn} ->
        browser_oauth_replay_redirect(conn, provider)

      {:csrf_error, conn} ->
        browser_oauth_error_redirect(conn, provider, "csrf_validation_failed")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Success."))
    |> UserAuth.log_out_user()
  end

  # API sign-in through a provider. Every one of these signs in: a bearer
  # token on the request is ignored. Linking a provider to the signed-in
  # account is `GamendWeb.Api.V1.ProviderController`, under `/api/v1/me`.

  @provider_path_param [
    in: :path,
    name: "provider",
    schema: %OpenApiSpex.Schema{
      type: :string,
      enum: ["discord", "apple", "google", "facebook", "github", "steam"]
    },
    description: "OAuth provider",
    required: true,
    example: "discord"
  ]

  operation(:api_request,
    operation_id: "oauth_request",
    summary: "Start a provider sign-in",
    description:
      "Answers the provider page to open and a session to poll with " <>
        "`GET /api/v1/auth/session/{session_id}` until the player finishes there. " <>
        "Always a sign-in; to link a provider to the signed-in account, " <>
        "`POST /api/v1/me/providers/{provider}/authorize`.",
    tags: ["Authentication"],
    parameters: [provider: @provider_path_param],
    responses: [
      ok: {"OAuth URL", "application/json", Schemas.OAuthAuthorizationResponse},
      not_found: Schemas.error("Unknown or disabled provider")
    ]
  )

  def api_request(conn, %{"provider" => provider}) do
    reply_data(conn, OAuthExchange.start_session(provider, %{}))
  end

  operation(:api_callback,
    operation_id: "oauth_api_callback",
    summary: "Sign in with a provider code",
    description:
      "Exchanges an authorization code (or, for Steam, a session ticket from " <>
        "`ISteamUser::GetAuthTicketForWebApi`) and signs in, finding or creating the " <>
        "account: the same `Session` as email and device login. Always a sign-in; to " <>
        "link a provider to the signed-in account, `POST /api/v1/me/providers/{provider}`.",
    tags: ["Authentication"],
    parameters: [provider: @provider_path_param],
    request_body: {
      "Provider code",
      "application/json",
      %OpenApiSpex.Schema{
        type: :object,
        required: [:code],
        properties: %{
          code: %OpenApiSpex.Schema{
            type: :string,
            description:
              "Authorization code; for Steam, a Steam auth ticket (hex), never a Steam id"
          }
        }
      }
    },
    responses: [
      ok: {"Signed in", "application/json", Schemas.SessionResponse},
      bad_request: Schemas.error("Missing code, or the provider refused it"),
      forbidden: Schemas.error("Account awaiting activation, or scheduled for deletion"),
      not_found: Schemas.error("Unknown or disabled provider"),
      unprocessable_entity: Schemas.error("The account could not be created")
    ]
  )

  def api_callback(conn, %{"provider" => provider} = params) do
    case OAuthExchange.code_params(provider, params["code"]) do
      {:ok, user_params} -> sign_in_api(conn, provider, user_params)
      {:error, reason} -> OAuthExchange.reply_refused(conn, reason)
    end
  end

  operation(:api_google_id_token,
    operation_id: "oauth_google_id_token",
    summary: "Sign in with a Google ID token",
    description:
      "Verifies a Google OpenID Connect `id_token` (Android Credential Manager, One Tap) " <>
        "and signs in. Always a sign-in; linking is " <>
        "`POST /api/v1/me/providers/google/id_token`.",
    tags: ["Authentication"],
    request_body: {
      "Google ID token",
      "application/json",
      %OpenApiSpex.Schema{
        type: :object,
        required: [:id_token],
        properties: %{
          id_token: %OpenApiSpex.Schema{
            type: :string,
            description:
              "Google OpenID Connect id_token JWT. Audience must match GOOGLE_WEB_CLIENT_ID or GOOGLE_CLIENT_ID."
          }
        }
      }
    },
    responses: [
      ok: {"Signed in", "application/json", Schemas.SessionResponse},
      bad_request: Schemas.error("Missing or invalid token"),
      forbidden: Schemas.error("Account awaiting activation, or scheduled for deletion"),
      unprocessable_entity: Schemas.error("The account could not be created"),
      service_unavailable: Schemas.error("Google sign-in not configured")
    ]
  )

  def api_google_id_token(conn, params) do
    case OAuthExchange.google_params(params["id_token"]) do
      {:ok, user_params} -> sign_in_api(conn, "google", user_params)
      {:error, reason} -> OAuthExchange.reply_refused(conn, reason)
    end
  end

  operation(:api_apple_ios_callback,
    operation_id: "oauth_callback_api_apple_ios",
    summary: "Sign in with Apple (native iOS)",
    description:
      "Exchanges a native iOS Sign in with Apple authorization code, issued to " <>
        "APPLE_IOS_CLIENT_ID, and signs in. Always a sign-in; linking is " <>
        "`POST /api/v1/me/providers/apple/ios`.",
    tags: ["Authentication"],
    request_body: {
      "Apple authorization code",
      "application/json",
      %OpenApiSpex.Schema{
        type: :object,
        required: [:code],
        properties: %{
          code: %OpenApiSpex.Schema{
            type: :string,
            description: "Apple authorization code from the native Sign in with Apple flow"
          },
          given_name: %OpenApiSpex.Schema{
            type: :string,
            description:
              "Given name from the credential. Apple hands it over only on the first " <>
                "authorization and never in the token; it fills a blank display name."
          },
          family_name: %OpenApiSpex.Schema{
            type: :string,
            description: "Family name from the credential, as `given_name`."
          }
        }
      }
    },
    responses: [
      ok: {"Signed in", "application/json", Schemas.SessionResponse},
      bad_request: Schemas.error("Missing code, or Apple refused it"),
      forbidden: Schemas.error("Account awaiting activation, or scheduled for deletion"),
      unprocessable_entity: Schemas.error("The account could not be created")
    ]
  )

  def api_apple_ios_callback(conn, params) do
    name = OAuthExchange.apple_name(params["given_name"], params["family_name"])

    case OAuthExchange.apple_ios_params(params["code"]) do
      {:ok, user_params} ->
        sign_in_api(conn, "apple", OAuthExchange.put_apple_name(user_params, name))

      {:error, reason} ->
        OAuthExchange.reply_refused(conn, reason)
    end
  end

  operation(:api_providers,
    operation_id: "list_auth_providers",
    summary: "List sign-in providers",
    description: "The OAuth providers a player may currently sign in with.",
    tags: ["Authentication"],
    responses: [
      ok: {"Enabled providers", "application/json", GamendWeb.Schemas.AuthProvidersResponse}
    ]
  )

  def api_providers(conn, _params) do
    reply_data(conn, Enum.map(Providers.enabled(), &Atom.to_string/1))
  end

  operation(:api_session_status,
    operation_id: "oauth_session_status",
    summary: "Poll a provider sign-in",
    description:
      "The state of a sign-in started with `GET /api/v1/auth/{provider}`. " <>
        "`session` carries the tokens once the player finished, and only on the " <>
        "first read after that; every other read has `session: null`.",
    tags: ["Authentication"],
    parameters: [
      session_id: [
        in: :path,
        name: "session_id",
        schema: %OpenApiSpex.Schema{type: :string},
        description: "Session ID from OAuth request",
        required: true
      ]
    ],
    responses: [
      ok: {"Session status", "application/json", Schemas.OAuthSessionStatusResponse},
      not_found: Schemas.error("Session not found")
    ]
  )

  def api_session_status(conn, %{"session_id" => session_id}) do
    case OAuthSessions.get_session(session_id) do
      # A link session is polled by its owner under /api/v1/me.
      %Gamend.OAuthSession{data: %{"link_user_id" => _}} ->
        reply_error(conn, :not_found, "session_not_found", "OAuth session not found")

      %Gamend.OAuthSession{status: status, data: data} ->
        # Hand the tokens over exactly once. They used to be re-served on every
        # read until retention pruned the row a day later, so the session id —
        # which travels in a redirect URL, and therefore through browser
        # history, proxies and access logs — stayed a bearer credential for 24
        # hours after the client had already collected it.
        session = session_of(data)
        if session, do: consume_session_tokens(session_id, data)

        reply_data(conn, %{
          status: status,
          error: Map.get(data, "error", ""),
          message: Map.get(data, "message", ""),
          session: session
        })

      nil ->
        reply_error(conn, :not_found, "session_not_found", "OAuth session not found")
    end
  end

  defp session_of(%{"access_token" => access_token} = data)
       when is_binary(access_token) and access_token != "" do
    %{
      access_token: access_token,
      refresh_token: Map.get(data, "refresh_token", ""),
      expires_in: Map.get(data, "expires_in", Tokens.access_ttl_seconds()),
      user_id: Map.get(data, "user_id", ""),
      username: Map.get(data, "username", ""),
      display_name: Map.get(data, "display_name", "")
    }
  end

  defp session_of(_data), do: nil

  # Blank the token fields on the stored row after they have been served once.
  # Anything else in `data` stays, so the client can still poll for status.
  defp consume_session_tokens(session_id, data) do
    Gamend.OAuthSessions.update_session(
      session_id,
      %{data: Map.drop(data, ~w(access_token refresh_token))}
    )
  end
end
