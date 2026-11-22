# `mix gamend.blog.discussions`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.blog.discussions.ex#L1)

Mirrors the blog into a repository's GitHub Discussions, one discussion per
post, through the `gh` CLI and its login.

    mix gamend.blog.discussions          # list the posts not posted yet
    mix gamend.blog.discussions --post   # post them, oldest first

A post counts as posted when a discussion's body links to it
(`<site>/blog/<slug>`), so one written by hand counts too. The listing never
fails: without `gh`, a login or a network it says so and stops, which is what
lets `precommit` run it. Posting is never automatic, since a post goes public
the moment it is created.

The host names where to post:

    config :gamend_core, :blog_discussions,
      repo: "appsinacup/gamend",
      site: "https://gamend.org",
      category: "Announcements",
      tagline: "One line added under every post."

The body is the post's markdown made to read on GitHub: links and pictures
absolute, hard-wrapped lines joined (GitHub keeps a newline as a break), and
a clip shown as its poster linked to the mp4.

# `body`

```elixir
@spec body(map(), map(), String.t()) :: String.t()
```

A post's markdown as a discussion body.

# `unposted`

```elixir
@spec unposted(map(), [map()], [String.t()]) :: [map()]
```

The posts no discussion body links to, oldest first.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
