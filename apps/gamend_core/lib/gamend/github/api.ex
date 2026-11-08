defmodule Gamend.GitHub.API do
  @moduledoc """
  The GitHub REST calls a GitHub App makes, and the credentials that make
  them.

  A GitHub App speaks with three different tokens and it is worth keeping
  them apart by name:

    * the **App JWT**, signed here with the App's private key, ten minutes
      long, and good only for asking about installations and minting the
      next kind;
    * an **installation token**, one hour, scoped to the repositories one
      installation was granted, and what clones a private repository and
      writes a check run;
    * a **user token**, from the OAuth code a person brings back from
      GitHub, used exactly once to ask which installations they may see.

  Nothing here decides who may do what; that is `Gamend.GitHub`. This module
  only knows how to ask. Every call merges `:github_req_options` from
  `:gamend_core`'s environment, which is how a test points it at a
  `Req.Test` stub.
  """

  require Logger
  require Gamend.HttpHeader, as: HttpHeader

  @api "https://api.github.com"
  @web "https://github.com"
  @version "2022-11-28"

  @type token :: String.t()
  @type result :: {:ok, term()} | {:error, term()}

  ## The App's own credential

  @doc """
  A JWT the App signs for itself. `iat` sits a minute in the past because
  GitHub rejects a token whose clock is ahead of its own, and `exp` stays
  under the ten-minute ceiling.

  `{:error, :invalid_private_key}` when the configured key is not an RSA
  private key in PEM. That is the operator's to fix, and every caller is on a
  path that has to end (a checkout, a check run), so it is an answer rather
  than a raise that left the job that asked running.
  """
  @spec app_jwt(String.t(), String.t() | nil) :: {:ok, token()} | {:error, :invalid_private_key}
  def app_jwt(app_id, private_key_pem) do
    with {:ok, jwk} <- private_key(private_key_pem) do
      now = System.system_time(:second)
      claims = %{"iat" => now - 60, "exp" => now + 540, "iss" => app_id}

      {_jws, jwt} =
        jwk
        |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "JWT"}, claims)
        |> JOSE.JWS.compact()

      {:ok, jwt}
    end
  end

  # `from_pem/1` answers `[]` for text with no PEM block in it, and raises
  # from `:public_key` for a block whose body is not base64. Rescued at that
  # one call, since a configured key that does not decode means exactly what
  # one that is absent does. A key that decodes to something other than RSA
  # cannot sign RS256 either.
  defp private_key(pem) when is_binary(pem) do
    case JOSE.JWK.from_pem(normalize_pem(pem)) do
      %JOSE.JWK{kty: {:jose_jwk_kty_rsa, _key}} = jwk -> {:ok, jwk}
      _other -> {:error, :invalid_private_key}
    end
  rescue
    ErlangError -> {:error, :invalid_private_key}
  end

  defp private_key(_none), do: {:error, :invalid_private_key}

  # A key pasted into an env file arrives with literal `\n` where the line
  # breaks were; the same repair the Apple provider makes.
  defp normalize_pem(pem), do: String.replace(pem, "\\n", "\n")

  ## Installations

  @doc "One installation, as the App sees it: its account and what it may reach."
  @spec installation(token(), integer()) :: result()
  def installation(app_jwt, installation_id) do
    get("/app/installations/#{installation_id}", app_jwt)
  end

  @doc """
  Mint an installation token. Answers the token and when it expires, so the
  caller can cache it for exactly as long as it is worth caching.
  """
  @spec installation_token(token(), integer()) ::
          {:ok, %{token: token(), expires_at: DateTime.t()}} | {:error, term()}
  def installation_token(app_jwt, installation_id) do
    case post("/app/installations/#{installation_id}/access_tokens", app_jwt, %{}) do
      {:ok, %{"token" => token, "expires_at" => expires_at}} ->
        {:ok, %{token: token, expires_at: parse_time(expires_at)}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Every repository an installation was granted, across all its pages.

  A hundred per page and a page cap that no real installation reaches: a
  token minted for one organisation cannot list somebody else's repositories
  anyway, so a runaway here costs requests, never data.
  """
  @spec installation_repositories(token()) :: {:ok, [map()]} | {:error, term()}
  def installation_repositories(installation_token) do
    paginate("/installation/repositories", installation_token, "repositories")
  end

  ## The person

  @doc "The user token an OAuth code proves. Nothing about the person is read here."
  @spec exchange_code(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, token()} | {:error, term()}
  def exchange_code(code, client_id, client_secret, redirect_uri) do
    form = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri: redirect_uri
    }

    # GitHub answers a bad code with 200 and an `error` key, so the status is
    # not the thing to check.
    case Req.post(req(url: @web <> "/login/oauth/access_token"), form: form) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} when is_binary(token) ->
        {:ok, token}

      {:ok, %{body: %{"error" => error}}} ->
        {:error, {:oauth, error}}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The installations this person may see, as GitHub answers the question."
  @spec user_installations(token()) :: {:ok, [map()]} | {:error, term()}
  def user_installations(user_token) do
    paginate("/user/installations", user_token, "installations")
  end

  ## Check runs

  @doc "Create a check run on `repo` (`owner/name`). Answers GitHub's object."
  @spec create_check_run(token(), String.t(), map()) :: result()
  def create_check_run(installation_token, repo, attrs) do
    post("/repos/#{repo}/check-runs", installation_token, attrs)
  end

  @doc "Overwrite a check run's state. Every field named is replaced."
  @spec update_check_run(token(), String.t(), integer(), map()) :: result()
  def update_check_run(installation_token, repo, check_run_id, attrs) do
    patch("/repos/#{repo}/check-runs/#{check_run_id}", installation_token, attrs)
  end

  ## Registration

  @doc """
  Turn the code GitHub hands back from a manifest form into the App: its id,
  slug, client pair, webhook secret and private key, in one answer. No
  credential goes with it: the code is the credential, and it is good once,
  for an hour.
  """
  @spec convert_manifest(String.t()) :: result()
  def convert_manifest(code) do
    path = "/app-manifests/#{URI.encode(code)}/conversions"

    case Req.post(req(url: api_url() <> path)) do
      {:ok, %{status: 201, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("github: post #{path} answered #{status}: #{message(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Plumbing

  defp get(path, token), do: request(:get, path, token, [])
  defp post(path, token, body), do: request(:post, path, token, json: body)
  defp patch(path, token, body), do: request(:patch, path, token, json: body)

  defp request(method, path, token, opts) do
    req = req(url: api_url() <> path, auth: {:bearer, token})

    case Req.request(req, [method: method] ++ opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("github: #{method} #{path} answered #{status}: #{message(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("github: #{method} #{path} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp paginate(path, token, key, page \\ 1, acc \\ []) do
    case request(:get, "#{path}?per_page=100&page=#{page}", token, []) do
      {:ok, %{^key => rows}} when is_list(rows) ->
        acc = acc ++ rows

        if length(rows) == 100 and page < 20 do
          paginate(path, token, key, page + 1, acc)
        else
          {:ok, acc}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req(opts) do
    Req.new(
      [
        headers: [
          {HttpHeader.accept(), "application/vnd.github+json"},
          {HttpHeader.x_github_api_version(), @version},
          {HttpHeader.user_agent(), "Gamend"}
        ],
        retry: false,
        receive_timeout: 15_000
      ] ++ opts ++ Application.get_env(:gamend_core, :github_req_options, [])
    )
  end

  defp api_url, do: Application.get_env(:gamend_core, :github_api_url, @api)

  defp message(%{"message" => message}) when is_binary(message), do: message
  defp message(_body), do: "no message"

  defp parse_time(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      # A token whose expiry cannot be read is treated as already stale, so
      # it is used once and never cached.
      _ -> DateTime.utc_now()
    end
  end
end
