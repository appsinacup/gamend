defmodule GameServerWeb.AuthController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  # Only use Ueberauth for Steam (OpenID), other providers use custom implementation
  plug Ueberauth, only: [:request, :callback], providers: [:steam]

  alias GameServer.Accounts
  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServer.OAuth.GoogleIDToken
  alias GameServer.OAuthSessions
  alias GameServerWeb.Auth.Guardian
  alias GameServerWeb.Schemas.OAuthSessionData
  alias GameServerWeb.UserAuth

  @browser_state_prefix "browser:"

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
        # Not a browser state — check if it's a valid API OAuthSession
        case OAuthSessions.get_session(session_id) do
          nil ->
            # No matching session — invalid state
            {:csrf_error, conn}

          _session ->
            {:api, session_id}
        end
    end
  end

  defp dispatch_browser_oauth_state(conn, browser_state) do
    case OAuthSessions.get_session(browser_state) do
      %{status: "pending"} = session ->
        # Consume state once. Do not fall back to Plug session cookies for browser
        # OAuth: Apple form_post callbacks can legitimately arrive without them.
        _ = OAuthSessions.update_session(browser_state, %{status: "completed"})

        conn = maybe_restore_browser_link_scope(conn, session)

        {:browser, conn}

      _ ->
        {:csrf_error, conn}
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

  # Optionally extract current user from JWT in Authorization header.
  # Returns {:ok, user} if valid JWT present, or {:ok, nil} if no JWT or invalid.
  # This allows the same endpoint to handle both login and linking.
  defp maybe_load_user_from_jwt(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Guardian.decode_and_verify(token, %{"typ" => "access"}) do
          {:ok, claims} ->
            case Guardian.resource_from_claims(claims) do
              {:ok, user} -> {:ok, user}
              _ -> {:ok, nil}
            end

          _ ->
            {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  # Create an OAuth session for the API flow.
  # If a JWT is present, stores the user_id in the data map for linking when the callback completes.
  defp create_api_oauth_session(conn, provider) do
    session_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    # Check if user is authenticated - if so, store their ID for linking
    data =
      case maybe_load_user_from_jwt(conn) do
        {:ok, %User{id: user_id}} ->
          %{link_user_id: user_id}

        {:ok, nil} ->
          %{}
      end

    GameServer.OAuthSessions.create_session(session_id, %{
      provider: provider,
      status: "pending",
      data: data
    })

    session_id
  end

  # Handle the session-based OAuth callback (browser redirect flow).
  # If link_user_id is present in the session data, links the provider instead of login.
  defp handle_session_oauth_callback(conn, session_id, user_params, provider) do
    config = oauth_provider!(provider)

    handle_session_oauth_callback(
      conn,
      session_id,
      user_params,
      config.id_field,
      config.changeset,
      config.finder
    )
  end

  defp handle_session_oauth_callback(
         conn,
         session_id,
         user_params,
         provider_id_field,
         changeset_fn,
         find_or_create_fn
       ) do
    # Check if this session has a link_user_id in its data (meaning we should link, not login)
    session = OAuthSessions.get_session(session_id)
    link_user_id = session && get_in(session.data, ["link_user_id"])

    if is_binary(link_user_id) do
      # This is a linking flow
      case Accounts.get_user!(link_user_id) do
        user ->
          case Accounts.link_account(user, user_params, provider_id_field, changeset_fn) do
            {:ok, _updated_user} ->
              OAuthSessions.create_session(session_id, %{
                status: "completed",
                data: %{linked: true, provider: Atom.to_string(provider_id_field)}
              })

              redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")

            {:error, {:conflict, _other_user}} ->
              OAuthSessions.create_session(session_id, %{
                status: "error",
                data: %{
                  error: "provider_already_linked",
                  message: "This provider is already linked to another account"
                }
              })

              redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")

            {:error, _changeset} ->
              OAuthSessions.create_session(session_id, %{
                status: "error",
                data: %{error: "link_failed", details: "internal_error"}
              })

              redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
          end
      end
    else
      # Normal login/create flow
      case find_or_create_fn.(user_params) do
        {:ok, user} ->
          if Accounts.user_activated?(user) do
            {:ok, access_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")

            {:ok, refresh_token, _} =
              Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {30, :days})

            Accounts.touch_last_seen(user)

            OAuthSessions.create_session(session_id, %{
              status: "completed",
              data: %{
                access_token: access_token,
                refresh_token: refresh_token,
                expires_in: 900,
                user_id: user.id
              }
            })

            redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
          else
            OAuthSessions.create_session(session_id, %{
              status: "error",
              data: %{
                error: "account_not_activated",
                message: "Your account is pending activation by an administrator."
              }
            })

            redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
          end

        {:error, changeset} ->
          OAuthSessions.create_session(session_id, %{
            status: "error",
            data: %{details: changeset.errors}
          })

          redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
      end
    end
  rescue
    Ecto.NoResultsError ->
      OAuthSessions.create_session(session_id, %{
        status: "error",
        data: %{error: "user_not_found", message: "The user to link to was not found"}
      })

      redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
  end

  # Handle linking a provider to an existing user (API flow)
  defp handle_api_link(conn, user, user_params, provider_id_field, changeset_fn) do
    case Accounts.link_account(user, user_params, provider_id_field, changeset_fn) do
      {:ok, _updated_user} ->
        json(conn, %{data: %{linked: true, provider: Atom.to_string(provider_id_field)}})

      {:error, {:conflict, _other_user}} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "provider_already_linked",
          message: "This provider is already linked to another account"
        })

      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "link_failed", details: "internal_error"})
    end
  end

  # Handle login/create flow (API) - returns JWT tokens
  defp handle_api_login(conn, find_or_create_fn, user_params) do
    case find_or_create_fn.(user_params) do
      {:ok, user} ->
        if Accounts.user_activated?(user) do
          {:ok, access_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")

          {:ok, refresh_token, _} =
            Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {30, :days})

          Accounts.touch_last_seen(user)

          json(conn, %{
            data: %{
              access_token: access_token,
              refresh_token: refresh_token,
              expires_in: 900,
              user_id: user.id
            }
          })
        else
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: "account_not_activated",
            message: "Your account is pending activation by an administrator."
          })
        end

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "create_failed", details: changeset.errors})
    end
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

  defp oauth_provider(provider) do
    case provider do
      "discord" ->
        {:ok,
         %{
           label: "Discord",
           id_field: :discord_id,
           changeset: &User.discord_oauth_changeset/2,
           finder: &Accounts.find_or_create_from_discord/1
         }}

      "google" ->
        {:ok,
         %{
           label: "Google",
           id_field: :google_id,
           changeset: &User.google_oauth_changeset/2,
           finder: &Accounts.find_or_create_from_google/1
         }}

      "facebook" ->
        {:ok,
         %{
           label: "Facebook",
           id_field: :facebook_id,
           changeset: &User.facebook_oauth_changeset/2,
           finder: &Accounts.find_or_create_from_facebook/1
         }}

      "apple" ->
        {:ok,
         %{
           label: "Apple",
           id_field: :apple_id,
           changeset: &User.apple_oauth_changeset/2,
           finder: &Accounts.find_or_create_from_apple/1
         }}

      "steam" ->
        {:ok,
         %{
           label: "Steam",
           id_field: :steam_id,
           changeset: &User.steam_oauth_changeset/2,
           finder: &Accounts.find_or_create_from_steam/1
         }}

      _ ->
        {:error, :unsupported_provider}
    end
  end

  defp oauth_provider!(provider) do
    {:ok, config} = oauth_provider(provider)
    config
  end

  defp exchange_oauth_code(provider, code, client_type \\ :web) do
    with {:ok, _config} <- oauth_provider(provider),
         {:ok, user_info} <- exchange_provider_code(provider, code, client_type) do
      oauth_user_params(provider, user_info)
    end
  end

  defp exchange_provider_code("discord", code, :web) do
    exchanger = oauth_exchanger()

    exchanger.exchange_discord_code(
      code,
      GameServer.Settings.get(GameServer.OAuth.Providers, :discord_client_id),
      GameServer.Settings.get(GameServer.OAuth.Providers, :discord_client_secret),
      oauth_redirect_uri("discord")
    )
  end

  defp exchange_provider_code("google", code, :web) do
    exchanger = oauth_exchanger()

    exchanger.exchange_google_code(
      code,
      GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_id),
      GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_secret),
      oauth_redirect_uri("google")
    )
  end

  defp exchange_provider_code("facebook", code, :web) do
    exchanger = oauth_exchanger()

    exchanger.exchange_facebook_code(
      code,
      GameServer.Settings.get(GameServer.OAuth.Providers, :facebook_client_id),
      GameServer.Settings.get(GameServer.OAuth.Providers, :facebook_client_secret),
      oauth_redirect_uri("facebook")
    )
  end

  defp exchange_provider_code("apple", code, client_type) when client_type in [:web, :ios] do
    exchanger = oauth_exchanger()
    client_id = if client_type == :ios, do: apple_ios_client_id(), else: apple_web_client_id()
    client_secret = apple_client_secret(client_id)
    exchanger.exchange_apple_code(code, client_id, client_secret, oauth_redirect_uri("apple"))
  end

  defp oauth_exchanger do
    Application.get_env(:game_server_web, :oauth_exchanger, GameServer.OAuth.Exchanger)
  end

  defp oauth_redirect_uri(provider) do
    "#{GameServerWeb.endpoint().url()}/auth/#{provider}/callback"
  end

  defp apple_client_secret(client_id) do
    GameServer.Apple.client_secret(client_id: client_id)
  rescue
    _ -> nil
  end

  defp oauth_user_params("discord", %{"id" => discord_id, "email" => email} = response) do
    avatar = response["avatar"]
    display_name = Map.get(response, "global_name") || Map.get(response, "username")

    {:ok,
     %{
       email: email,
       email_verified: verified_email?(response["verified"]),
       discord_id: discord_id,
       display_name: display_name,
       profile_url:
         if(avatar,
           do: "https://cdn.discordapp.com/avatars/#{discord_id}/#{avatar}.png",
           else: nil
         )
     }}
  end

  defp oauth_user_params("google", %{"id" => google_id, "email" => email} = user_info) do
    picture = Map.get(user_info, "picture")
    name = Map.get(user_info, "name") || Map.get(user_info, "given_name")

    user_params = %{
      email: email,
      email_verified: verified_email?(user_info["email_verified"] || user_info["verified_email"]),
      google_id: google_id,
      display_name: name
    }

    {:ok, if(picture, do: Map.put(user_params, :profile_url, picture), else: user_params)}
  end

  defp oauth_user_params("facebook", %{"id" => facebook_id} = user_info) do
    profile_url =
      user_info
      |> Map.get("picture", %{})
      |> Map.get("data", %{})
      |> Map.get("url")

    user_params = %{
      email: user_info["email"],
      # Facebook does not expose a per-login email-verification claim, so its
      # emails are never trusted for auto-linking to an existing account.
      email_verified: false,
      facebook_id: facebook_id,
      display_name: Map.get(user_info, "name")
    }

    {:ok, if(profile_url, do: Map.put(user_params, :profile_url, profile_url), else: user_params)}
  end

  defp oauth_user_params("apple", %{"sub" => apple_id} = user_info) do
    {:ok,
     %{
       email: user_info["email"],
       email_verified: verified_email?(user_info["email_verified"]),
       apple_id: apple_id,
       display_name: Map.get(user_info, "name")
     }}
  end

  defp oauth_user_params("steam", %{"id" => steam_id} = profile_info) do
    {:ok,
     %{
       steam_id: steam_id,
       display_name: Map.get(profile_info, "display_name"),
       profile_url: Map.get(profile_info, "profile_url")
     }}
  end

  defp oauth_user_params(_provider, _user_info), do: {:error, :missing_user_info}

  # Providers report email verification as either a boolean or a "true" string.
  defp verified_email?(true), do: true
  defp verified_email?("true"), do: true
  defp verified_email?(_), do: false

  defp handle_api_oauth_result(conn, provider, user_params) do
    config = oauth_provider!(provider)

    case maybe_load_user_from_jwt(conn) do
      {:ok, %User{} = current_user} ->
        handle_api_link(
          conn,
          current_user,
          user_params,
          config.id_field,
          config.changeset
        )

      {:ok, nil} ->
        handle_api_login(conn, config.finder, user_params)
    end
  end

  defp handle_browser_oauth_callback(conn, provider, user_params) do
    config = oauth_provider!(provider)

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

            conn
            |> put_flash(:error, gettext("Failed"))
            |> redirect(
              to:
                ~p"/users/settings?conflict_provider=#{provider}&conflict_user_id=#{other_user.id}"
            )

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
    Application.get_env(:game_server_web, :environment, :prod) == :dev
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
          enum: ["discord", "apple", "google", "facebook", "steam"]
        },
        required: true
      ]
    ],
    responses: [
      found: {"Redirect to provider", "text/html", %OpenApiSpex.Schema{type: :string}}
    ]
  )

  def request(conn, %{"provider" => "discord"}) do
    cfg = Application.get_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth, [])
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :discord_client_id)

    base = GameServerWeb.endpoint().url()
    redirect_uri = cfg[:redirect_uri] || "#{base}/auth/discord/callback"
    scope = "identify email"
    {conn, state} = put_oauth_state(conn, "discord")

    url =
      "https://discord.com/oauth2/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  # steam_callback helper is defined with the other callbacks below

  # Steam callback handlers live alongside other provider callbacks below

  def request(conn, %{"provider" => "google"}) do
    cfg = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_id)

    base = GameServerWeb.endpoint().url()
    redirect_uri = cfg[:redirect_uri] || "#{base}/auth/google/callback"
    scope = "email profile"
    {conn, state} = put_oauth_state(conn, "google")

    url =
      "https://accounts.google.com/o/oauth2/v2/auth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&access_type=offline&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  def request(conn, %{"provider" => "facebook"}) do
    cfg = Application.get_env(:ueberauth, Ueberauth.Strategy.Facebook.OAuth, [])
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :facebook_client_id)

    base = GameServerWeb.endpoint().url()
    redirect_uri = cfg[:redirect_uri] || "#{base}/auth/facebook/callback"
    scope = "email"
    {conn, state} = put_oauth_state(conn, "facebook")

    url =
      "https://www.facebook.com/v18.0/dialog/oauth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(state)}"

    redirect(conn, external: url)
  end

  def request(conn, %{"provider" => "apple"}) do
    cfg = Application.get_env(:ueberauth, Ueberauth.Strategy.Apple.OAuth, [])
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id)

    base = GameServerWeb.endpoint().url()
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
      when provider in ["discord", "google", "facebook", "apple"] do
    case exchange_oauth_code(provider, code) do
      {:ok, user_params} ->
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
        case OAuthSessions.get_session(session_id) do
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
            GameServer.OAuthSessions.create_session(session_id, %{
              status: "error",
              data: %{details: "authentication_failed"}
            })

            redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")
        end
    end
  end

  # Catch-all for missing code or unsupported providers
  def callback(conn, params) do
    require Logger

    Logger.error(
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

      {:csrf_error, conn} ->
        browser_oauth_error_redirect(conn, provider, "csrf_validation_failed")
    end
  end

  defp handle_oauth_state_error(conn, provider, error, state) do
    case dispatch_oauth_state(conn, state) do
      {:browser, conn} ->
        browser_oauth_error_redirect(conn, provider, error)

      {:api, session_id} ->
        GameServer.OAuthSessions.create_session(session_id, %{
          status: "error",
          data: %{details: "authentication_failed"}
        })

        redirect(conn, to: ~p"/auth/success?session_id=#{session_id}")

      {:csrf_error, conn} ->
        browser_oauth_error_redirect(conn, provider, "csrf_validation_failed")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Success."))
    |> UserAuth.log_out_user()
  end

  # API OAuth endpoints
  operation(:api_request,
    operation_id: "oauth_request",
    summary: "Initiate API OAuth",
    description: "Returns OAuth authorization URL for API clients",
    tags: ["Authentication"],
    parameters: [
      provider: [
        in: :path,
        name: "provider",
        schema: %OpenApiSpex.Schema{
          type: :string,
          enum: ["discord", "apple", "google", "facebook", "steam"]
        },
        description: "OAuth provider",
        required: true,
        example: "discord"
      ]
    ],
    responses: [
      ok: {
        "OAuth URL",
        "application/json",
        %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            authorization_url: %OpenApiSpex.Schema{
              type: :string,
              description: "URL to redirect user to for OAuth"
            },
            session_id: %OpenApiSpex.Schema{
              type: :string,
              description: "Unique session ID to track this OAuth request"
            }
          },
          example: %{
            authorization_url: "https://discord.com/oauth2/authorize?...",
            session_id: "abc123..."
          }
        }
      }
    ]
  )

  operation(:api_callback,
    operation_id: "oauth_api_callback",
    summary: "API callback / code exchange",
    description:
      "Accepts an OAuth authorization code via the API and returns access/refresh tokens on success. " <>
        "If a valid JWT is provided in the Authorization header, the provider will be **linked** to the authenticated user instead of logging in. " <>
        "For the Steam provider, the `code` field should contain a server-verifiable Steam credential (for example a Steam auth ticket or Steam identifier) and will be validated via the Steam Web API.",
    tags: ["Authentication"],
    parameters: [
      provider: [
        in: :path,
        name: "provider",
        schema: %OpenApiSpex.Schema{type: :string},
        required: true
      ]
    ],
    request_body: {
      "Code exchange or steam payload",
      "application/json",
      %OpenApiSpex.Schema{
        type: :object,
        properties: %{
          code: %OpenApiSpex.Schema{
            type: :string,
            description:
              "Authorization code (for code-based providers). For Steam provider this MUST be a Steam auth ticket (AuthenticateUserTicket) and NOT a steam id."
          }
        }
      }
    },
    responses: [
      ok:
        {"OAuth tokens", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{data: OAuthSessionData}
         }},
      bad_request: {"Bad request", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def api_request(conn, %{"provider" => "discord"}) do
    # Create session (with optional link_user_id if JWT is present)
    session_id = create_api_oauth_session(conn, "discord")

    # Generate the Discord OAuth URL with state parameter
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :discord_client_id)
    base = GameServerWeb.endpoint().url()
    redirect_uri = "#{base}/auth/discord/callback"
    scope = "identify email"

    url =
      "https://discord.com/oauth2/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(session_id)}"

    json(conn, %{authorization_url: url, session_id: session_id})
  end

  def api_request(conn, %{"provider" => "apple"}) do
    # Create session (with optional link_user_id if JWT is present)
    session_id = create_api_oauth_session(conn, "apple")

    # Generate the Apple OAuth URL
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id)
    base = GameServerWeb.endpoint().url()
    redirect_uri = "#{base}/auth/apple/callback"
    scope = "name email"

    url =
      "https://appleid.apple.com/auth/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&response_mode=form_post&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(session_id)}"

    json(conn, %{authorization_url: url, session_id: session_id})
  end

  def api_request(conn, %{"provider" => "google"}) do
    # Create session (with optional link_user_id if JWT is present)
    session_id = create_api_oauth_session(conn, "google")

    # Generate the Google OAuth URL
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :google_client_id)
    base = GameServerWeb.endpoint().url()
    redirect_uri = "#{base}/auth/google/callback"
    scope = "email profile"

    url =
      "https://accounts.google.com/o/oauth2/v2/auth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&access_type=offline&state=#{URI.encode_www_form(session_id)}"

    json(conn, %{authorization_url: url, session_id: session_id})
  end

  def api_request(conn, %{"provider" => "facebook"}) do
    # Create session (with optional link_user_id if JWT is present)
    session_id = create_api_oauth_session(conn, "facebook")

    # Generate the Facebook OAuth URL
    client_id = GameServer.Settings.get(GameServer.OAuth.Providers, :facebook_client_id)
    base = GameServerWeb.endpoint().url()
    redirect_uri = "#{base}/auth/facebook/callback"
    scope = "email"

    url =
      "https://www.facebook.com/v18.0/dialog/oauth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&state=#{URI.encode_www_form(session_id)}"

    json(conn, %{authorization_url: url, session_id: session_id})
  end

  def api_request(conn, %{"provider" => "steam"}) do
    # Create session (with optional link_user_id if JWT is present)
    session_id = create_api_oauth_session(conn, "steam")

    base = GameServerWeb.endpoint().url()

    # For Steam OpenID, include the session_id in the return_to callback so
    # the callback handler can treat this as an API/session flow when the
    # session_id is present.
    return_to = "#{base}/auth/steam/callback?state=#{URI.encode_www_form(session_id)}"
    realm = base

    url =
      "https://steamcommunity.com/openid/login?openid.ns=http://specs.openid.net/auth/2.0&openid.mode=checkid_setup&openid.return_to=#{URI.encode_www_form(return_to)}&openid.realm=#{URI.encode_www_form(realm)}&openid.identity=http://specs.openid.net/auth/2.0/identifier_select&openid.claimed_id=http://specs.openid.net/auth/2.0/identifier_select"

    json(conn, %{authorization_url: url, session_id: session_id})
  end

  # Unknown provider
  def api_request(conn, %{"provider" => _provider}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_provider", message: "Unsupported OAuth provider"})
  end

  # API clients can POST a code (or steam_id) to the callback endpoint and receive
  # tokens directly. Supports discord, google, facebook, apple and steam (steam via steam_id).
  # If a valid JWT is provided in Authorization header, links the provider instead of login.
  operation(:api_google_id_token,
    operation_id: "oauth_google_id_token",
    summary: "Google ID token login (native/mobile)",
    description:
      "Verify a Google OpenID Connect id_token (eg. from Android Credential Manager) and return JWT tokens.",
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
      ok:
        {"OAuth tokens", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{data: GameServerWeb.Schemas.OAuthSessionData}
         }},
      bad_request: {"Bad request", "application/json", %OpenApiSpex.Schema{type: :object}},
      internal_server_error:
        {"Server misconfigured", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def api_google_id_token(conn, %{"id_token" => id_token}) when is_binary(id_token) do
    case GoogleIDToken.verify(id_token) do
      {:ok, claims} ->
        user_params = %{
          google_id: Map.get(claims, "sub"),
          email: Map.get(claims, "email"),
          email_verified: verified_email?(Map.get(claims, "email_verified")),
          display_name: Map.get(claims, "name"),
          profile_url: Map.get(claims, "picture")
        }

        # Check if user is authenticated (linking) or not (login)
        case maybe_load_user_from_jwt(conn) do
          {:ok, %User{} = current_user} ->
            handle_api_link(
              conn,
              current_user,
              user_params,
              :google_id,
              &User.google_oauth_changeset/2
            )

          {:ok, nil} ->
            handle_api_login(conn, &Accounts.find_or_create_from_google/1, user_params)
        end

      {:error, :missing_google_client_id} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "server_misconfigured",
          message: "Missing GOOGLE_WEB_CLIENT_ID/GOOGLE_CLIENT_ID"
        })

      {:error, :invalid_audience} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_token", message: "Invalid audience"})

      {:error, :invalid_issuer} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_token", message: "Invalid issuer"})

      {:error, :expired} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_token", message: "Token expired"})

      {:error, _err} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_token", details: "authentication_failed"})
    end
  end

  def api_google_id_token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_param", message: "id_token is required"})
  end

  def api_callback(conn, %{"provider" => provider, "code" => code})
      when provider in ["discord", "google", "facebook", "apple"] do
    case exchange_oauth_code(provider, code) do
      {:ok, user_params} ->
        handle_api_oauth_result(conn, provider, user_params)

      {:error, :missing_user_info} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "exchange_failed", details: "missing id/email"})

      {:error, _err} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "exchange_failed", details: "authentication_failed"})
    end
  end

  # For steam, allow clients to POST an object with a steam_id (and optional display_name/profile_url)
  # and return tokens on success.
  # Steam: verify the provided `code` with the configured exchanger (uses Steam Web API)
  # For steam, allow clients to POST either a steam SDK `ticket` (preferred for SDK flows)
  # or a `code`/steam_id. If `ticket` is present prefer exchange_steam_ticket which
  # verifies the client-provided ticket via the Steam Web API. Otherwise fall back to
  # exchange_steam_code which validates a steam id or steam-specific code.
  def api_callback(conn, %{"provider" => "steam"} = params) do
    # For API Steam flows, the 'code' field MUST be a Steam auth ticket
    # issued by the client (AuthenticateUserTicket). We prefer the stronger
    # AuthenticateUserTicket verification and explicitly DO NOT accept plain
    # steam ids via the API (they remain supported in the browser OpenID flow).
    exchange_result =
      case params["code"] do
        nil -> {:error, :missing_param}
        code -> oauth_exchanger().exchange_steam_ticket(code, fetch_profile: true)
      end

    case exchange_result do
      {:ok, profile_info} ->
        case oauth_user_params("steam", profile_info) do
          {:ok, user_params} ->
            handle_api_oauth_result(conn, "steam", user_params)

          {:error, _} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "exchange_failed", details: "authentication_failed"})
        end

      {:error, :missing_param} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "missing_param",
          message: "code (Steam auth ticket) is required for steam provider"
        })

      {:error, _err} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "exchange_failed", details: "authentication_failed"})
    end
  end

  def api_callback(conn, %{"provider" => _provider}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "missing_or_unsupported",
      message: "provider or required params are missing/unsupported"
    })
  end

  operation(:api_apple_ios_callback,
    operation_id: "oauth_callback_api_apple_ios",
    summary: "Apple callback (native iOS)",
    description:
      "Exchanges a native iOS Sign in with Apple authorization code using APPLE_IOS_CLIENT_ID.",
    tags: ["Authentication"],
    request_body: {
      "Apple callback params",
      "application/json",
      %OpenApiSpex.Schema{
        type: :object,
        required: [:code],
        properties: %{
          code: %OpenApiSpex.Schema{
            type: :string,
            description: "Apple authorization code from the native Sign in with Apple flow"
          }
        }
      }
    },
    responses: [
      ok:
        {"OAuth tokens", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{data: OAuthSessionData}
         }},
      bad_request: {"Bad request", "application/json", GameServerWeb.Schemas.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", GameServerWeb.Schemas.ErrorResponse}
    ]
  )

  def api_apple_ios_callback(conn, %{"code" => code}) do
    case exchange_oauth_code("apple", code, :ios) do
      {:ok, user_params} ->
        handle_api_oauth_result(conn, "apple", user_params)

      {:error, _err} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "exchange_failed", details: "authentication_failed"})
    end
  end

  def api_apple_ios_callback(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_code"})
  end

  defp apple_web_client_id do
    GameServer.Settings.get(GameServer.OAuth.Providers, :apple_client_id) ||
      raise "GAMEND_OAUTH_APPLE_CLIENT_ID is not set"
  end

  defp apple_ios_client_id do
    GameServer.Settings.get(GameServer.OAuth.Providers, :apple_ios_client_id) ||
      raise "GAMEND_OAUTH_APPLE_IOS_CLIENT_ID is not set"
  end

  operation(:api_session_status,
    operation_id: "oauth_session_status",
    summary: "Get OAuth session status",
    description: "Check the status of an OAuth session for API clients",
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
      ok: {"Session status", "application/json", GameServerWeb.Schemas.OAuthSessionStatus},
      not_found: {
        "Session not found",
        "application/json",
        %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            error: %OpenApiSpex.Schema{type: :string},
            message: %OpenApiSpex.Schema{type: :string}
          },
          required: [:error, :message]
        }
      }
    ]
  )

  def api_session_status(conn, %{"session_id" => session_id}) do
    case GameServer.OAuthSessions.get_session(session_id) do
      %GameServer.OAuthSession{status: status, data: data} ->
        {message, normalized_data} = pop_session_message(data)

        json(conn, %{
          status: status,
          message: message,
          data: normalized_data
        })

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session_not_found", message: "OAuth session not found"})
    end
  end

  defp pop_session_message(data) do
    message =
      Map.get(data, "message") ||
        Map.get(data, :message) ||
        ""

    cleaned =
      data
      |> Map.delete("message")
      |> Map.delete(:message)

    {message, cleaned}
  end
end
