# `Gamend.GitHub`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/github.ex#L1)

The server's GitHub App: who may use which installation, the credentials a
job borrows from it, and what its webhook means.

For a host that works on its customers' repositories: Forge builds them,
Gamend Cloud builds a server from one. Core keeps what every such host
needs (the App's settings, its tokens, the installations a user connected,
the connect flow at `/github/*`, `/admin/github`, `mix gamend.github.app`);
the host keeps what it binds to a repository (a project, a server) and the
webhook route that acts on it.

## Two credentials, two owners

The App's OAuth client id and secret are its identity to a *person*:
`Gamend.OAuth.Providers` declares them as `github`, so "Log in with GitHub"
is the same App, and the connect flow here reads the same pair. The App id,
slug and private key are what mint installation tokens, and are declared on
this module (`GAMEND_GITHUB_*`). Both are operator configuration; neither
is a customer's, so neither lives in `Gamend.Secrets`.

## Who may use an installation

GitHub decides. After the App is installed, `GET /user/installations` with
the person's own token lists the installations that person may see, and
those rows, only those, become theirs in `github_installations`. Trusting
the `installation_id` GitHub appends to the setup redirect would let anyone
type a number into a URL and claim somebody else's organisation. A host
that binds something to an installation checks `get_installation/2` first.

## Where the token goes

Into `git`'s environment (`git_env/1`), and nowhere else. A clone URL
carrying it is written to the clone's `.git/config`, which a build may
read; a log that prints the repository URL never had it.

## The webhook

The App has one webhook URL, the host's route. The host verifies a delivery
with `verify_webhook/2` over the raw body, hands every verified one to
`installation_event/2` (which keeps this module's rows in step and says
what the host has to unbind), and reads a push with `push_event/1`.

# `app_jwt`

```elixir
@spec app_jwt() :: {:ok, String.t()} | {:error, :invalid_private_key}
```

A fresh App JWT. Never cached: it is cheap and ten minutes long. Logged at
error level when the configured key cannot sign one, since nothing that
asked for it can work until the operator fixes the setting.

# `authorize_url`

```elixir
@spec authorize_url(String.t(), String.t()) :: String.t()
```

Where to send a person so GitHub can tell us which installations are
theirs. `state` is the OAuth session id the callback consumes;
`redirect_uri` is the callback, registered on the App.

# `config`

```elixir
@spec config(atom()) :: term()
```

Read one of this group's settings.

# `configured?`

```elixir
@spec configured?() :: boolean()
```

Whether the App is set up end to end: its own three settings, and the
client pair that the connect flow and the login button both use.

# `count_all_installations`

```elixir
@spec count_all_installations() :: non_neg_integer()
```

How many installations the server holds, across every user.

# `count_installations`

```elixir
@spec count_installations(String.t()) :: non_neg_integer()
```

Count for `list_installations/1`.

# `forget_installation_token`

```elixir
@spec forget_installation_token(integer()) :: :ok
```

Drop a cached installation token. An uninstalled App's token is dead on
GitHub's side already; this stops a job in flight from trying it.

# `get_installation`

```elixir
@spec get_installation(Gamend.Accounts.User.t(), integer()) ::
  Gamend.GitHub.Installation.t() | nil
```

One of a user's installations, by GitHub's id. `nil` if it is not theirs.

# `git_env`

```elixir
@spec git_env(integer() | nil) :: {:ok, [{String.t(), String.t()}]} | {:error, term()}
```

The environment a `git` needs to clone through an installation.

Empty for none. Otherwise the token rides in as an `http.extraheader` for
github.com only: `git` reads it, nothing the clone writes holds it, and
`ps` shows only the variable names. Prompting is switched off so a token
GitHub refuses fails the clone rather than hanging the job.

# `install_url`

```elixir
@spec install_url() :: String.t()
```

Where a customer installs the App on their account or organisation.

# `installation_deleted`

```elixir
@spec installation_deleted(integer()) :: :ok
```

The App was uninstalled: every user's row for it goes, and its cached token.
What the host bound to it is the host's to unbind (`installation_event/2`
answers `{:deleted, id}`).

# `installation_event`

```elixir
@spec installation_event(String.t() | nil, map()) ::
  {:deleted, integer()} | {:repositories_removed, integer(), [integer()]} | :ok
```

The App's own lifecycle, from a verified delivery's `X-GitHub-Event` and
payload. This module's rows follow it here; the answer is what the host
has to unbind:

  * `{:deleted, installation_id}`: the App was uninstalled;
  * `{:repositories_removed, installation_id, repo_ids}`: the installation
    no longer reaches those repositories;
  * `:ok`: nothing for the host (a suspension, any other event).

An uninstall is the customer withdrawing access, so what borrowed it stops
the moment GitHub says so rather than at the next failed clone.

# `installation_suspended`

```elixir
@spec installation_suspended(integer(), DateTime.t() | nil) :: :ok
```

Record that GitHub suspended, or reinstated, an installation.

# `installation_token`

```elixir
@spec installation_token(integer()) :: {:ok, String.t()} | {:error, term()}
```

An installation token, cached until five minutes before GitHub expires it.

Cached under `Gamend.Cache` rather than in the process: jobs for one
installation run in parallel and each would otherwise mint its own, and
GitHub counts those against the App.

# `link_installations`

```elixir
@spec link_installations(Gamend.Accounts.User.t(), String.t(), String.t()) ::
  {:ok, [Gamend.GitHub.Installation.t()]} | {:error, term()}
```

Turn the code a person brought back into their installations.

The user token is used for exactly one request and dropped: nothing here
needs to act as the person later, and a token that is not stored cannot
leak. What is kept is GitHub's answer, the installations, written as this
user's. Ones GitHub no longer lists are removed, so revoking access on
GitHub's side is enough to revoke it here.

# `list_all_installations`

```elixir
@spec list_all_installations(keyword()) :: [map()]
```

Every installation on this server, newest first, for `/admin/github`.

Each row carries the user who connected it and, when the host counts them
(`config :gamend_core, :github_usage, {module, function}`, answering
`%{installation_id => count}`), how many of the host's things use it in
`uses` (`nil` when the host counts nothing). A suspended or unused
installation is then visible as such: the first is GitHub's doing and the
second is a customer who left.

# `list_installations`

```elixir
@spec list_installations(String.t()) :: [Gamend.GitHub.Installation.t()]
```

The installations a user connected, by account name.

# `push_event`

```elixir
@spec push_event(map()) ::
  {:ok,
   %{
     ref: String.t(),
     branch: String.t() | nil,
     sha: String.t(),
     repo_id: integer() | nil,
     repo_urls: [String.t()]
   }}
  | {:error, atom()}
```

What a `push` payload means: the ref and commit pushed, the branch when it
is one, and the repository by GitHub's id and its URLs.

A delete carries no commit and is `{:error, :deleted}`.

# `repositories`

```elixir
@spec repositories(Gamend.Accounts.User.t(), integer()) ::
  {:ok, [map()]} | {:error, :not_linked | term()}
```

The repositories a user's installation may reach, for a picker. Only the
fields a form needs, so a GitHub response shape change stays out here.

# `repository`

```elixir
@spec repository(Gamend.Accounts.User.t(), integer(), integer()) ::
  {:ok, map()} | {:error, :not_linked | :not_found | term()}
```

One repository of a user's installation, by GitHub's id: GitHub's answer,
so a host binds only a repository the installation really reaches.

# `unlink_installation`

```elixir
@spec unlink_installation(Gamend.Accounts.User.t(), integer()) :: :ok
```

Forget one of a user's installations. The App stays installed on GitHub.

# `usage`

```elixir
@spec usage() :: %{required(integer()) =&gt; non_neg_integer()} | nil
```

What the host's usage callback answers, or `nil` when it counts nothing
(`list_all_installations/1`).

# `verify_webhook`

```elixir
@spec verify_webhook(binary(), String.t() | nil) :: :ok | {:error, atom()}
```

Verify a delivery's `X-Hub-Signature-256` against the raw request body.

Over the raw body, in constant time, and never over the parsed params,
which are a re-encoding and would let a crafted payload pass a check its
own bytes would fail. Refuses when no secret is configured: an endpoint
anyone can POST to and that starts work must not be open by default.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
