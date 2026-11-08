defmodule Gamend.GitHub.Manifest do
  @moduledoc """
  The server's GitHub App, described once, so GitHub creates it rather than a
  person filling in a form.

  GitHub has no API for creating or editing an App's settings: the callback
  URLs, the setup URL, the permissions all live on a page only a browser
  reaches. What it does have is the manifest flow: a form posts this JSON to
  `github.com/settings/apps/new`, the person signed in there presses one
  button, and GitHub redirects to `redirect_url` with a code that
  `convert/1` trades for everything `.env` needs (id, slug, client pair,
  webhook secret and the private key) in one answer. `mix gamend.github.app`
  is that flow end to end.

  What the App is called, says and may do is the host's:

      config :gamend_core, Gamend.GitHub.Manifest,
        name: "Gamend Cloud",
        description: "Builds a Gamend server from your repository.",
        webhook_path: "/cloud/hooks/github",
        permissions: %{"checks" => "write"}

  `permissions` are added to the floor every App gets (contents and metadata
  read, to clone and list; email addresses read, so "Log in with GitHub"
  finds an account by its verified email). Without a `webhook_path` the App
  has no webhook and subscribes to nothing.

  Two things the manifest cannot say. The installation events (`installation`,
  `installation_repositories`) are not subscribable: every App with a
  webhook receives them, so only `push` is listed. And "expire user
  authorization tokens" has no field; GitHub turns it on for every new App,
  which is what the connect flow wants.
  """

  alias Gamend.GitHub.API

  @push "push"

  @name "Gamend"
  @description "Sign in with GitHub, and the repositories you choose."
  @callback_paths ["/auth/github/callback", "/github/callback"]
  @setup_path "/github/setup"
  @permissions %{"contents" => "read", "metadata" => "read", "emails" => "read"}

  @typedoc "What GitHub answers for a converted manifest."
  @type app :: %{
          app_id: String.t(),
          slug: String.t(),
          client_id: String.t(),
          client_secret: String.t(),
          webhook_secret: String.t() | nil,
          private_key: String.t(),
          html_url: String.t() | nil
        }

  @doc "The App's default name, the host's or Gamend's. App names are global, so it may be taken."
  @spec default_name() :: String.t()
  def default_name, do: Keyword.get(host(), :name, @name)

  @doc """
  The manifest for an App serving `host_url`.

  Every URL is built from it, so the two callbacks (the login and the
  connect flow), the setup URL and the webhook agree with the routes by
  construction rather than by copying them into a form.
  """
  @spec build(String.t(), keyword()) :: map()
  def build(host_url, opts) do
    host_url = String.trim_trailing(host_url, "/")
    config = host()

    manifest = %{
      "name" => Keyword.get(opts, :name, default_name()),
      "url" => host_url,
      "description" => Keyword.get(config, :description, @description),
      "redirect_url" => Keyword.fetch!(opts, :redirect_url),
      "callback_urls" => Enum.map(@callback_paths, &(host_url <> &1)),
      "setup_url" => host_url <> @setup_path,
      "setup_on_update" => true,
      "public" => true,
      "request_oauth_on_install" => false,
      "default_permissions" => Map.merge(@permissions, Keyword.get(config, :permissions, %{}))
    }

    case Keyword.get(config, :webhook_path) do
      nil ->
        manifest

      path ->
        manifest
        |> Map.put("hook_attributes", %{"url" => host_url <> path, "active" => true})
        |> Map.put("default_events", Keyword.get(config, :events, [@push]))
    end
  end

  @doc "Every URL a manifest names, for the page that shows it before the button."
  @spec urls(map()) :: [String.t()]
  def urls(manifest) do
    [manifest["url"] | manifest["callback_urls"]] ++
      [manifest["setup_url"] | List.wrap(get_in(manifest, ["hook_attributes", "url"]))]
  end

  @doc """
  Where the form posts: the person's own account, or an organisation they
  administer. `state` comes back on the redirect, which is how the callback
  knows the code belongs to this run.
  """
  @spec form_action(String.t() | nil, String.t()) :: String.t()
  def form_action(nil, state) do
    "https://github.com/settings/apps/new?state=" <> URI.encode_www_form(state)
  end

  def form_action(org, state) do
    "https://github.com/organizations/#{URI.encode(org)}/settings/apps/new?state=" <>
      URI.encode_www_form(state)
  end

  @doc "Trade the code for the App."
  @spec convert(String.t()) :: {:ok, app()} | {:error, term()}
  def convert(code) do
    with {:ok, body} <- API.convert_manifest(code) do
      {:ok,
       %{
         app_id: to_string(body["id"]),
         slug: body["slug"],
         client_id: body["client_id"],
         client_secret: body["client_secret"],
         webhook_secret: body["webhook_secret"],
         private_key: body["pem"],
         html_url: body["html_url"]
       }}
    end
  end

  @doc """
  The settings, as `.env` lines. The key's line breaks are written as a
  literal `\\n` inside quotes: compose expands them, and `Gamend.GitHub.API`
  repairs them if something does not. No webhook secret without a webhook.
  """
  @spec env_lines(app()) :: [String.t()]
  def env_lines(app) do
    pem = app.private_key |> String.trim() |> String.replace("\n", "\\n")

    [
      "GAMEND_OAUTH_GITHUB_CLIENT_ID=#{app.client_id}",
      "GAMEND_OAUTH_GITHUB_CLIENT_SECRET=#{app.client_secret}",
      "GAMEND_GITHUB_APP_ID=#{app.app_id}",
      "GAMEND_GITHUB_APP_SLUG=#{app.slug}",
      ~s(GAMEND_GITHUB_PRIVATE_KEY="#{pem}")
    ] ++
      if app.webhook_secret in [nil, ""],
        do: [],
        else: ["GAMEND_GITHUB_WEBHOOK_SECRET=#{app.webhook_secret}"]
  end

  defp host, do: Application.get_env(:gamend_core, __MODULE__, [])
end
