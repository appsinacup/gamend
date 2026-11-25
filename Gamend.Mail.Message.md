# `Gamend.Mail.Message`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/mail/message.ex#L1)

What an email says, before it has a look: every email core sends
(`Gamend.Accounts.UserNotifier`) is one of these, so they all share one
layout and read as the same site's.

  * `title`: the heading (the subject is set apart, often the same words);
  * `paragraphs`: the text, one string a paragraph;
  * `button`: `{label, url}`, the one thing the email asks you to do;
  * `code`: six digits to type in a game, drawn large;
  * `image`: an absolute URL, drawn under the heading (a blog post's picture);
  * `items`: a digest's notices, `%{title, text, url}` each;
  * `footer`: small lines at the bottom (why you get it, how to stop it).

`to_text/1` is the plain-text copy every email carries. The HTML copy is the
website's (`GamendWeb.MailLayout`: the site's name, logo and colour), which
core reaches by name, as it queues the web's mail jobs by name: a core with
no website sends the text alone.

# `item`

```elixir
@type item() :: %{
  title: String.t() | nil,
  text: String.t() | nil,
  url: String.t() | nil
}
```

# `t`

```elixir
@type t() :: %Gamend.Mail.Message{
  button: {String.t(), String.t()} | nil,
  code: String.t() | nil,
  footer: [String.t()],
  image: String.t() | nil,
  items: [item()],
  paragraphs: [String.t()],
  title: String.t()
}
```

# `to_html`

```elixir
@spec to_html(t()) :: String.t() | nil
```

The HTML copy, or nil when there is no website to draw it.

# `to_text`

```elixir
@spec to_text(t()) :: String.t()
```

The plain-text copy: the same words, the button as its link.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
