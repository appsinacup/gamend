# `Gamend.GitHub.Manifest`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/github/manifest.ex#L1)

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

# `app`

```elixir
@type app() :: %{
  app_id: String.t(),
  slug: String.t(),
  client_id: String.t(),
  client_secret: String.t(),
  webhook_secret: String.t() | nil,
  private_key: String.t(),
  html_url: String.t() | nil
}
```

What GitHub answers for a converted manifest.

# `build`

```elixir
@spec build(String.t(), keyword()) :: map()
```

The manifest for an App serving `host_url`.

Every URL is built from it, so the two callbacks (the login and the
connect flow), the setup URL and the webhook agree with the routes by
construction rather than by copying them into a form.

# `convert`

```elixir
@spec convert(String.t()) :: {:ok, app()} | {:error, term()}
```

Trade the code for the App.

# `default_name`

```elixir
@spec default_name() :: String.t()
```

The App's default name, the host's or Gamend's. App names are global, so it may be taken.

# `env_lines`

```elixir
@spec env_lines(app()) :: [String.t()]
```

The settings, as `.env` lines. The key's line breaks are written as a
literal `\n` inside quotes: compose expands them, and `Gamend.GitHub.API`
repairs them if something does not. No webhook secret without a webhook.

# `form_action`

```elixir
@spec form_action(String.t() | nil, String.t()) :: String.t()
```

Where the form posts: the person's own account, or an organisation they
administer. `state` comes back on the redirect, which is how the callback
knows the code belongs to this run.

# `urls`

```elixir
@spec urls(map()) :: [String.t()]
```

Every URL a manifest names, for the page that shows it before the button.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
