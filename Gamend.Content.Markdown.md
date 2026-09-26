# `Gamend.Content.Markdown`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/content/markdown.ex#L1)

Markdown to HTML, the way every collection renders it.

One pipeline: strip the frontmatter, mend table separators, parse with
MDEx, rewrite the tree — code-language aliases, mermaid fences,
admonitions, links written to a neighbouring `.md` — render through the
sanitiser, then fix up image paths on the HTML.

The rewrites work on `MDEx.Document` nodes rather than on rendered HTML: a
fence inside a list item is still a `MDEx.CodeBlock`, a `:::tip` inside a
quote still a `MDEx.BlockDirective`, and a link's `url` is a field rather
than an attribute a regex has to find. The one pass left on the HTML is the
image one, because a `<figure>` written in raw HTML carries an `<img>` no
node stands for, and every image gets the same `loading`/`decoding`
attributes either way.

## Raw HTML

Rendered with `unsafe: true` and *always* sanitised. The allowlist below is
what makes that safe: a fixed set of tags a guide legitimately contains —
`<figure>`, `<video>`, `<details>`, a `<div class>` for a gallery, an
inline `<svg>` for an icon — with the attributes each of them needs and
nothing that runs. Content is the operator's own files, so the sanitiser
is a guard against a pasted snippet, not against an adversary; it stays on
because a rule that is on for everyone is a rule nobody has to remember.

## Admonitions

Two spellings, one markup. `:::tip[Title]` … `:::` is what Docusaurus
authors write; `> [!TIP]` is GitHub's. MDEx parses the first as a
`MDEx.BlockDirective` whose `info` is `tip[Title]` and the second as a
`MDEx.Alert`. Both become a directive rendered as
`<div class="admonition admonition-tip">` with a
`<p class="admonition-title">` as its first child, which is the one thing
a stylesheet has to know. A raw `<div class="note">` an author wrote is
HTML, not a directive, and stays as written.

# `opt`

```elixir
@type opt() ::
  {:collection, String.t()}
  | {:assets, :content | :static}
  | {:dir, String.t()}
  | {:base_path, String.t() | nil}
  | {:slug, String.t() | nil}
  | {:index, boolean()}
  | {:id, String.t()}
```

* `:collection` — the registered name, for `/content/<collection>/` asset paths
* `:assets` — `:content` (the default) rewrites image paths into the
  collection's asset route; `:static` leaves root-absolute paths alone, for
  a site whose images are served from `priv/static`
* `:dir` — the file's folder relative to the collection root, for relative
  image paths
* `:base_path` — the route prefix a `.md` link rewrites to; `nil` leaves
  such links untouched
* `:slug` — the document's slug, which relative links resolve against
* `:index` — the document is a folder's `index.md`, whose slug *is* its
  folder, so its links resolve against the slug rather than its parent.
  `render_file/2` sets it from the file name.
* `:id` — a stable prefix for element ids (mermaid diagrams need one)

# `plain_text`

```elixir
@spec plain_text(String.t()) :: String.t()
```

Inline markup removed, entities left as they are.

# `render`

```elixir
@spec render(String.t(), [opt()]) :: {:ok, String.t()} | {:error, term()}
```

Render markdown source. The frontmatter, if any, is dropped.

# `render_file`

```elixir
@spec render_file(Path.t(), [opt()]) :: String.t() | nil
```

Render a file, or `nil` when it cannot be read or parsed.

# `sections`

```elixir
@spec sections(String.t() | nil) :: [
  %{id: String.t(), text: String.t(), level: 2 | 3, lede: String.t() | nil}
]
```

The `h2` and `h3` sections of rendered HTML: each heading as `toc/1` gives
it, plus `:lede`, the first sentence of the paragraph that opens the
section, or nil when the section opens with a list, a table or code.

# `strip_first_h1`

```elixir
@spec strip_first_h1(String.t()) :: String.t()
```

Drop a leading `<h1>`: the page renders the title itself, so leaving it in
prints it twice. Attribute-tolerant, because headings carry ids now.

# `toc`

```elixir
@spec toc(String.t() | nil) :: [%{id: String.t(), text: String.t(), level: 2 | 3}]
```

The headings of rendered HTML, for a table of contents: `h2` and `h3`
with their ids and plain text.

Read from the HTML because that is what the cache holds; the renderer
puts the id first on the heading tag, so the pattern is stable.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
