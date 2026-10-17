defmodule GamendWeb.Auth.OAuthExchange do
  @moduledoc """
  What signing in and linking through a provider share: the provider table,
  the authorization URL a client opens, and turning what the provider hands
  back (a code, a Steam ticket, a Google ID token) into the user attributes
  `Gamend.Accounts` finds, creates or links an account with.

  Signing in is `GamendWeb.AuthController`, linking is
  `GamendWeb.Api.V1.ProviderController`; neither decides the other's case.
  """

  import GamendWeb.Reply

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.OAuth.GoogleIDToken
  alias Gamend.OAuthSessions

  @type provider :: String.t()
  @type config :: %{
          label: String.t(),
          id_field: atom(),
          changeset: (User.t(), map() -> Ecto.Changeset.t()),
          finder: (map() -> {:ok, User.t()} | {:error, term()})
        }

  @providers ~w(discord google facebook github apple steam)

  @doc "The providers the API names in a path."
  @spec providers() :: [provider()]
  def providers, do: @providers

  @doc "A provider's account field, changeset and finder."
  @spec provider(provider()) :: {:ok, config()} | {:error, :unsupported_provider}
  def provider("discord") do
    {:ok,
     %{
       label: "Discord",
       id_field: :discord_id,
       changeset: &User.discord_oauth_changeset/2,
       finder: &Accounts.find_or_create_from_discord/1
     }}
  end

  def provider("google") do
    {:ok,
     %{
       label: "Google",
       id_field: :google_id,
       changeset: &User.google_oauth_changeset/2,
       finder: &Accounts.find_or_create_from_google/1
     }}
  end

  def provider("facebook") do
    {:ok,
     %{
       label: "Facebook",
       id_field: :facebook_id,
       changeset: &User.facebook_oauth_changeset/2,
       finder: &Accounts.find_or_create_from_facebook/1
     }}
  end

  def provider("github") do
    {:ok,
     %{
       label: "GitHub",
       id_field: :github_id,
       changeset: &User.github_oauth_changeset/2,
       finder: &Accounts.find_or_create_from_github/1
     }}
  end

  def provider("apple") do
    {:ok,
     %{
       label: "Apple",
       id_field: :apple_id,
       changeset: &User.apple_oauth_changeset/2,
       finder: &Accounts.find_or_create_from_apple/1
     }}
  end

  def provider("steam") do
    {:ok,
     %{
       label: "Steam",
       id_field: :steam_id,
       changeset: &User.steam_oauth_changeset/2,
       finder: &Accounts.find_or_create_from_steam/1
     }}
  end

  def provider(_provider), do: {:error, :unsupported_provider}

  @spec provider!(provider()) :: config()
  def provider!(name) do
    {:ok, config} = provider(name)
    config
  end

  @doc """
  The page a client opens to sign in or link, carrying `state` (the OAuth
  session id) back to `/auth/<provider>/callback`.
  """
  @spec authorization_url(provider(), String.t()) :: String.t()
  def authorization_url("discord", state) do
    query(
      "https://discord.com/oauth2/authorize",
      client_id: setting(:discord_client_id),
      redirect_uri: redirect_uri("discord"),
      response_type: "code",
      scope: "identify email",
      state: state
    )
  end

  def authorization_url("apple", state) do
    query(
      "https://appleid.apple.com/auth/authorize",
      client_id: setting(:apple_client_id),
      redirect_uri: redirect_uri("apple"),
      response_type: "code",
      response_mode: "form_post",
      scope: "name email",
      state: state
    )
  end

  def authorization_url("google", state) do
    query(
      "https://accounts.google.com/o/oauth2/v2/auth",
      client_id: setting(:google_client_id),
      redirect_uri: redirect_uri("google"),
      response_type: "code",
      scope: "email profile",
      access_type: "offline",
      state: state
    )
  end

  def authorization_url("facebook", state) do
    query(
      "https://www.facebook.com/v18.0/dialog/oauth",
      client_id: setting(:facebook_client_id),
      redirect_uri: redirect_uri("facebook"),
      response_type: "code",
      scope: "email",
      state: state
    )
  end

  # No `scope`: a GitHub App ignores it, its permissions are set on the App.
  def authorization_url("github", state) do
    query(
      "https://github.com/login/oauth/authorize",
      client_id: setting(:github_client_id),
      redirect_uri: redirect_uri("github"),
      state: state
    )
  end

  # Steam is OpenID, run by Ueberauth, whose callback checks a state cookie
  # only its own request phase sets. So the page is that request,
  # `/auth/steam`, in the browser that will sign in; the session id rides
  # along and waits for the callback in the Plug session
  # (`GamendWeb.AuthController`'s `stash_steam_session/2`).
  def authorization_url("steam", session_id) do
    query("#{GamendWeb.endpoint().url()}/auth/steam", session_id: session_id)
  end

  @doc """
  Start a polled flow: a pending OAuth session the provider's callback
  completes, and the page that gets it there. `data` is what the callback
  needs to know; `%{link_user_id: id}` makes it link instead of sign in.
  """
  @spec start_session(provider(), map()) :: %{
          authorization_url: String.t(),
          session_id: String.t()
        }
  def start_session(provider, data) do
    session_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    OAuthSessions.create_session(session_id, %{
      provider: provider,
      status: "pending",
      data: data
    })

    %{authorization_url: authorization_url(provider, session_id), session_id: session_id}
  end

  @doc """
  What a provider code proves: an authorization code for the OAuth providers,
  a session ticket for Steam.
  """
  @spec code_params(provider(), term()) :: {:ok, map()} | {:error, term()}
  def code_params("steam", ticket), do: steam_ticket(ticket)

  def code_params(provider, code) when is_binary(code) and code != "",
    do: exchange_code(provider, code)

  def code_params(_provider, _code), do: {:error, :missing_param}

  @doc "What a Google ID token proves."
  @spec google_params(term()) :: {:ok, map()} | {:error, term()}
  def google_params(id_token) when is_binary(id_token) and id_token != "",
    do: google_id_token(id_token)

  def google_params(_id_token), do: {:error, :missing_id_token}

  @doc "What a native Sign in with Apple code proves."
  @spec apple_ios_params(term()) :: {:ok, map()} | {:error, term()}
  def apple_ios_params(code) when is_binary(code) and code != "",
    do: exchange_code("apple", code, :ios)

  def apple_ios_params(_code), do: {:error, :missing_param}

  @doc """
  The display name from Apple's web `user` form field: a JSON string,
  `{"name": {"firstName", "lastName"}, "email"}`. Apple sends it only on a
  player's FIRST authorization and never puts the name in the ID token, so
  dropping it here loses it for good.
  """
  @spec apple_web_name(term()) :: String.t() | nil
  def apple_web_name(user) when is_binary(user) do
    case Jason.decode(user) do
      {:ok, %{"name" => %{} = name}} -> apple_name(name["firstName"], name["lastName"])
      _ -> nil
    end
  end

  def apple_web_name(_user), do: nil

  @doc """
  "Given Family", trimmed, or nil when both are blank. A name past the
  display-name limit is dropped whole rather than cut: kept, it would fail
  the changeset and with it the whole sign-in.
  """
  @spec apple_name(term(), term()) :: String.t() | nil
  def apple_name(given, family) do
    [given, family]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> case do
      "" -> nil
      # Codepoints, as the changeset and the column count them.
      name -> if length(String.codepoints(name)) <= Gamend.Limits.get(:max_display_name), do: name
    end
  end

  @doc "Sets the Apple-provided name when there is one; a nil keeps the params."
  @spec put_apple_name(map(), String.t() | nil) :: map()
  def put_apple_name(user_params, nil), do: user_params
  def put_apple_name(user_params, name), do: Map.put(user_params, :display_name, name)

  @doc "The answer to a code, ticket or token the provider would not vouch for."
  @spec reply_refused(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def reply_refused(conn, :missing_param),
    do: reply_error(conn, :bad_request, "missing_param", "code is required")

  def reply_refused(conn, :missing_id_token),
    do: reply_error(conn, :bad_request, "missing_param", "id_token is required")

  def reply_refused(conn, :missing_google_client_id) do
    reply_error(
      conn,
      :service_unavailable,
      "google_not_configured",
      "Missing GOOGLE_WEB_CLIENT_ID/GOOGLE_CLIENT_ID"
    )
  end

  def reply_refused(conn, reason) when reason in [:invalid_audience, :invalid_issuer, :expired],
    do: reply_error(conn, :bad_request, "invalid_token", Atom.to_string(reason))

  def reply_refused(conn, :missing_user_info),
    do: reply_error(conn, :bad_request, "exchange_failed", "missing id/email")

  def reply_refused(conn, _reason),
    do: reply_error(conn, :bad_request, "exchange_failed", "authentication_failed")

  @doc """
  Exchange an authorization code for the user attributes it proves. `:ios`
  is the native Sign in with Apple code, issued to the iOS client id.
  """
  @spec exchange_code(provider(), String.t(), :web | :ios) ::
          {:ok, map()} | {:error, term()}
  def exchange_code(provider, code, client_type \\ :web) do
    with {:ok, _config} <- provider(provider),
         {:ok, user_info} <- exchange_provider_code(provider, code, client_type) do
      user_params(provider, user_info)
    end
  end

  @doc """
  Verify a Steam session ticket (`AuthenticateUserTicket`) with the Steam Web
  API. A bare Steam id is not accepted: only the browser OpenID flow proves
  one.
  """
  @spec steam_ticket(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def steam_ticket(ticket) when is_binary(ticket) and ticket != "" do
    with {:ok, profile_info} <- exchanger().exchange_steam_ticket(ticket, fetch_profile: true) do
      user_params("steam", profile_info)
    end
  end

  def steam_ticket(_ticket), do: {:error, :missing_param}

  @doc "Verify a Google OpenID Connect ID token (Android Credential Manager, One Tap)."
  @spec google_id_token(String.t()) :: {:ok, map()} | {:error, term()}
  def google_id_token(id_token) do
    with {:ok, claims} <- GoogleIDToken.verify(id_token) do
      {:ok,
       %{
         google_id: Map.get(claims, "sub"),
         email: Map.get(claims, "email"),
         email_verified: verified_email?(Map.get(claims, "email_verified")),
         display_name: Map.get(claims, "name"),
         profile_url: Map.get(claims, "picture")
       }}
    end
  end

  @doc "The attributes a provider's profile gives an account."
  @spec user_params(provider(), map()) :: {:ok, map()} | {:error, :missing_user_info}
  def user_params("discord", %{"id" => discord_id, "email" => email} = response) do
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

  def user_params("google", %{"id" => google_id, "email" => email} = user_info) do
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

  def user_params("facebook", %{"id" => facebook_id} = user_info) do
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

  # GitHub's `id` is an integer in its JSON; the column is a string.
  def user_params("github", %{"id" => github_id} = user_info) do
    {:ok,
     %{
       email: user_info["email"],
       email_verified: verified_email?(user_info["email_verified"]),
       github_id: to_string(github_id),
       display_name: Map.get(user_info, "name") || Map.get(user_info, "login"),
       profile_url: Map.get(user_info, "avatar_url")
     }}
  end

  def user_params("apple", %{"sub" => apple_id} = user_info) do
    {:ok,
     %{
       email: user_info["email"],
       email_verified: verified_email?(user_info["email_verified"]),
       apple_id: apple_id,
       display_name: Map.get(user_info, "name")
     }}
  end

  def user_params("steam", %{"id" => steam_id} = profile_info) do
    {:ok,
     %{
       steam_id: steam_id,
       display_name: Map.get(profile_info, "display_name"),
       profile_url: Map.get(profile_info, "profile_url")
     }}
  end

  def user_params(_provider, _user_info), do: {:error, :missing_user_info}

  @doc "Where a provider sends the player back to."
  @spec redirect_uri(provider()) :: String.t()
  def redirect_uri(provider), do: "#{GamendWeb.endpoint().url()}/auth/#{provider}/callback"

  defp exchange_provider_code("discord", code, :web) do
    exchanger().exchange_discord_code(
      code,
      setting(:discord_client_id),
      setting(:discord_client_secret),
      redirect_uri("discord")
    )
  end

  defp exchange_provider_code("google", code, :web) do
    exchanger().exchange_google_code(
      code,
      setting(:google_client_id),
      setting(:google_client_secret),
      redirect_uri("google")
    )
  end

  defp exchange_provider_code("facebook", code, :web) do
    exchanger().exchange_facebook_code(
      code,
      setting(:facebook_client_id),
      setting(:facebook_client_secret),
      redirect_uri("facebook")
    )
  end

  defp exchange_provider_code("github", code, :web) do
    exchanger().exchange_github_code(
      code,
      setting(:github_client_id),
      setting(:github_client_secret),
      redirect_uri("github")
    )
  end

  defp exchange_provider_code("apple", code, client_type) when client_type in [:web, :ios] do
    client_id = if client_type == :ios, do: apple_ios_client_id(), else: apple_web_client_id()

    exchanger().exchange_apple_code(
      code,
      client_id,
      apple_client_secret(client_id),
      redirect_uri("apple")
    )
  end

  defp exchange_provider_code(_provider, _code, _client_type), do: {:error, :unsupported_provider}

  defp exchanger do
    Application.get_env(:gamend_web, :oauth_exchanger, Gamend.OAuth.Exchanger)
  end

  defp setting(key), do: Gamend.Settings.get(Gamend.OAuth.Providers, key)

  defp apple_web_client_id do
    setting(:apple_client_id) || raise "GAMEND_OAUTH_APPLE_CLIENT_ID is not set"
  end

  defp apple_ios_client_id do
    setting(:apple_ios_client_id) || raise "GAMEND_OAUTH_APPLE_IOS_CLIENT_ID is not set"
  end

  # Without the log this surfaces only as Apple's opaque `invalid_client`: a
  # nil secret and a genuinely rejected one look identical from the outside.
  defp apple_client_secret(client_id) do
    Gamend.Apple.client_secret(client_id: client_id)
  rescue
    error ->
      require Logger

      Logger.error("Apple OAuth: could not build client secret: #{Exception.message(error)}")
      nil
  end

  # Providers report email verification as either a boolean or a "true" string.
  defp verified_email?(true), do: true
  defp verified_email?("true"), do: true
  defp verified_email?(_), do: false

  defp query(base, params), do: base <> "?" <> URI.encode_query(params)
end
