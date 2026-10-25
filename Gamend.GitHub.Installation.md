# `Gamend.GitHub.Installation`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/github/installation.ex#L1)

One user's access to one installation of the GitHub App.

The row is written from `GET /user/installations`, answered with the user's
own GitHub token: GitHub's word on what that person may see, rather than a
number they typed into a URL. `installation_id` is GitHub's; the primary key
is ours and never leaves the server.

# `t`

```elixir
@type t() :: %Gamend.GitHub.Installation{
  __meta__: term(),
  account_id: term(),
  account_login: term(),
  account_type: term(),
  id: term(),
  inserted_at: term(),
  installation_id: term(),
  repository_selection: term(),
  suspended_at: term(),
  updated_at: term(),
  user_id: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
