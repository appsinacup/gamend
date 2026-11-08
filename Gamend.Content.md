# `Gamend.Content`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/content.ex#L1)

Reads and renders Markdown content from project files and directories.

Lookup is path-based rather than theme-config driven. Hosts register named
content sources, and this module resolves whichever configured files or
directories exist for those sources.

All content is cached in `:persistent_term` after the first read.
Call `reload/0` to invalidate everything (e.g. after a config change).

The work is split three ways and this module is the door to all of it:
`Gamend.Content.Frontmatter` reads the `---` block, `Gamend.Content.Markdown`
turns a file into HTML, and `Gamend.Content.Tree` reads a nested guide
collection. What stays here is the registry, the cache, the blog, and the
changelog and roadmap pills.

# `apply_changelog_pills`

```elixir
@spec apply_changelog_pills(String.t()) :: String.t()
```

Converts `[tag]` markers in changelog or roadmap HTML into coloured badges.

A catch-all: any `[word]` becomes a pill, known tags in their own colour and
everything else in the neutral one. That is deliberate for a changelog, where
every line opens with a marker and an unrecognised one is a typo worth
seeing — unlike the guide, where brackets are prose.

Applied inside `changelog_html/0` and `roadmap_html/0`, so the result is
cached. Labels here are **English literals and must stay that way**: a
translated label baked into the cache would be served to every other locale.
A host that wants translated pills re-labels them per request — see `pill/2`.

# `asset_path`

```elixir
@spec asset_path(atom() | String.t(), String.t()) :: String.t() | nil
```

Returns the absolute path for a picture, sound or video relative to a
registered content source. Returns `nil` when not found, when path traversal
is attempted, and for any other kind of file.

# `blog_neighbours`

```elixir
@spec blog_neighbours(String.t()) :: {map() | nil, map() | nil}
```

Returns `{prev_post, next_post}` neighbours for the given slug (newest-first order).
Either may be `nil`.

# `blog_post_html`

```elixir
@spec blog_post_html(String.t()) :: String.t() | nil
```

Renders a blog post's markdown to HTML, or `nil`.

# `blog_posts_grouped`

```elixir
@spec blog_posts_grouped() :: [{integer(), [{integer(), [map()]}]}]
```

Groups blog posts by `{year, month}` (newest first).
Returns a list of `{year, [{month, [posts]}]}`.

# `changelog_html`

```elixir
@spec changelog_html() :: String.t() | nil
```

Returns the rendered changelog HTML, or `nil` when the changelog path is
not configured or the file doesn't exist.

# `doc_breadcrumbs`

```elixir
@spec doc_breadcrumbs(atom(), String.t()) :: [Gamend.Content.Tree.entry()]
```

The categories above a guide, outermost first, then the guide. For a
breadcrumb. Empty in a flat collection, whose one level the index already
shows.

# `doc_category`

```elixir
@spec doc_category(atom(), String.t()) :: map() | nil
```

The category a guide belongs to — its display title, icon and colour — or
`nil`.

Found by membership rather than by name: a guide carries its category's
*folder* ("10-setup") while the category carries the display title ("Setup").
Both pages that render a guide need this, so deriving it twice by hand was
how the two drifted apart.

In a tree collection this is the guide's nearest category, with its
`guides` being that category's direct pages.

# `doc_html`

```elixir
@spec doc_html(atom(), String.t()) :: String.t() | nil
```

Renders a guide's markdown to HTML, or `nil`.

The leading `# ` heading is dropped: the page renders the title itself, so
leaving it in would print it twice.

A collection registered with `:post_render` runs that `{module, function}`
over the finished HTML — the hook Polyglot Pirates' guide uses to turn
`[coins:250]` into a badge. It runs *after* markdown rendering because the
sanitiser strips raw HTML out of the markdown, and inside the cache because
the result is as static as the markdown it came from. One registered with
`:image_url` has its pictures swapped the same way, inside the cache.

# `doc_neighbours`

```elixir
@spec doc_neighbours(atom(), String.t()) :: {map() | nil, map() | nil}
```

`{previous, next}` guides around `slug` in reading order, either possibly
`nil`.

Across categories, not within one: the collections are written to be read
front to back, and stopping at a category boundary would strand the reader on
the last page of each section.

# `doc_sections`

```elixir
@spec doc_sections(atom(), String.t()) :: [
  %{id: String.t(), text: String.t(), level: 2 | 3, lede: String.t() | nil}
]
```

A guide's `h2` and `h3` sections: the heading's id and text, as
`doc_toc/2` gives them, plus `:lede`, the first sentence of the section's
first paragraph (nil when it opens with a list, a table or code).

For search: a section is a place to go as much as a guide is. Cached until
`reload/0`, like the HTML it is read from.

# `doc_toc`

```elixir
@spec doc_toc(atom(), String.t()) :: [
  %{id: String.t(), text: String.t(), level: 2 | 3}
]
```

The headings of a rendered guide, for a table of contents.

# `doc_tree`

```elixir
@spec doc_tree(atom()) :: [Gamend.Content.Tree.entry()]
```

The whole tree of a `nesting: :tree` collection — categories with their
children, guides with their metadata — in reading order. A flat collection
answers its categories as top-level nodes, so a sidebar built from this
works on either.

# `frontmatter`

```elixir
@spec frontmatter(String.t()) :: Gamend.Content.Frontmatter.meta()
```

Reads a leading `---` fenced block.

Deliberately not YAML — see `Gamend.Content.Frontmatter` for exactly how
much of it is read. Scalars come back as strings, numbers or booleans, and
lists as lists.

# `get_blog_post`

```elixir
@spec get_blog_post(String.t()) :: map() | nil
```

Returns a single blog post map by slug, or `nil`.

# `get_doc`

```elixir
@spec get_doc(atom(), String.t()) :: map() | nil
```

Returns a single guide map by slug, or `nil`.

# `get_doc_category`

```elixir
@spec get_doc_category(atom(), String.t()) :: Gamend.Content.Tree.category() | nil
```

A category of a tree collection by its slug, or `nil`. A category without
an `index.md` has no guide of its own, and this is how its page is found.

# `image_url`

```elixir
@spec image_url(atom() | String.t(), String.t() | nil, :page | :card) ::
  String.t() | nil
```

The URL to serve an image of a collection at, through the collection's
registered `:image_url` (see `register_path/2`): `use` is `:page` or
`:card`. Without one, or for an `http`/`data:` URL, `url` itself.

The rendered HTML and `list_blog_posts/0` already went through it; this is
for a picture a page places itself, such as a post's cover.

# `list_blog_posts`

```elixir
@spec list_blog_posts() :: [map()]
```

Lists all blog posts sorted newest-first.

Each post is a map with keys:
  * `:slug`  – from frontmatter `slug`, else the filename after its date
  * `:title` – frontmatter `title`, else the first `# ` heading, else the
    humanised slug
  * `:date`  – frontmatter `date`, else the `YYYY-MM-DD-` filename prefix,
    else today
  * `:path`  – absolute path to the `.md` file
  * `:excerpt` – what a card and a meta description show: the frontmatter
    `description`, else the text above a `<!-- truncate -->` marker, else
    the first paragraph cut to 200 characters
  * `:lede` – the first paragraph in full, which is what a post opens
    with when it has no description of its own; `:lede_in_body?` says
    whether that paragraph is also the body's first, so the page drops one
  * `:image` – the post's picture, for its card, its feed entry and a link
    to it: the frontmatter `image`, else the first picture in the body, at
    the URL the body serves it from (`Gamend.Content.Markdown.image_src/2`,
    so a relative path is a `/content/blog/…` one); nil when it has none
  * `:card_image` – `:image` as the index card shows it: through the
    blog's registered `:image_url` with `:card`, else the same
  * `:description`, `:keywords`, `:tags` – frontmatter
  * `:authors` – resolved from `_authors/<key>.md` beside the posts:
    `%{key, name, title, url, image}`, with a key that has no file
    answering its key as its name
  * `:reading_minutes` – at two hundred words a minute, never under one

# `list_doc_categories`

```elixir
@spec list_doc_categories(atom()) :: [%{category: String.t() | nil, guides: [map()]}]
```

Lists every guide in a collection, grouped into categories in reading order.

Structure comes from the file tree rather than front matter, so a guide is a
file and nothing else has to be edited to add one:

    priv/docs/10-core-setup/20-deployment.md

The numeric prefixes order categories and guides and are stripped from the
slug; the folder name is the category; the title is the first `# ` heading.
Returns `[%{category: String.t(), guides: [guide]}]`, each guide a map of
`:slug`, `:title`, `:summary` and `:path`.

## Collections

A *collection* is the registered path name the guides are read from, so one
app can serve several unrelated sets — gamend serves `:docs`, Polyglot
Pirates serves both `:docs` (engineering, admin-only) and `:guide` (the
player guide). The collection is part of every cache key, so the sets never
see each other's entries. Everything defaults to `:docs`, which is what the
single-collection callers already had.

A collection registered with `nesting: :tree` answers the same shape for
its top-level categories, each holding every guide beneath it in reading
order; guides at the root come first under a category titled `nil`. The
full tree is `doc_tree/1`.

# `list_docs`

```elixir
@spec list_docs(atom()) :: [map()]
```

Every guide as a flat list, in reading order.

For a flat collection that is the order of `list_doc_categories/1`. For a
tree it is the tree's own order — a category's page, then its children,
then the next sibling — which is what previous/next should follow and what
the grouped view, with the root guides pulled to the front, does not.

# `memoize`

```elixir
@spec memoize(term(), (-&gt; value)) :: value when value: term()
```

Caches `fun`'s result under `key` until the next `reload/0`, for data a host
derives from content (its search entries, say) so it is built once rather
than on every request. An empty result is not cached.

# `path`

```elixir
@spec path(atom() | String.t()) :: String.t() | nil
```

Returns the resolved absolute path for a registered content source, or `nil`.

# `pill`

```elixir
@spec pill(String.t(), String.t()) :: String.t()
```

One pill badge: `class_suffix` picks the colour, `label` is what it reads.

The markup lives here rather than at each call site because a host that adds
its own tags — Polyglot Pirates re-labels the roadmap's in the reader's
language — was copying this line, class name and all, and would not notice
the day the stylesheet changed underneath it.

# `register_path`

```elixir
@spec register_path(atom() | String.t(), keyword()) :: :ok
```

Registers a named content source.

Supported options:
  * `:kind` - `:file` or `:dir`
  * `:path` - single candidate path
  * `:candidates` - ordered candidate paths
  * `:asset_root` - `:self` or `:dirname` when serving assets
  * `:post_render` - `{module, function}` applied to a guide's or a blog
    post's rendered HTML
  * `:visible` - `{module, function}` called as `function(guide)` for each
    guide of a collection; one it answers `false` for is left out of every
    listing and lookup (index, tree, previous/next, `get_doc/2`), so its
    URL is a 404. Run on every call, outside the cache, so a switch that
    changes at runtime takes effect at once. A category left with no guide
    goes too. `GamendWeb.Features.doc_visible?/1` hides a guide whose front
    matter names a switched-off feature (`feature: play`)
  * `:nesting` - `:flat` (the default: one folder level, slugs are file
    names) or `:tree` (any depth, slugs are paths; see `Gamend.Content.Tree`)
  * `:base_path` - the route prefix guides are served under, such as
    `"/docs"`. With it set, a link written to a neighbouring `.md` file is
    rewritten to that guide's route
  * `:assets` - `:content` (the default) serves images through the
    `/content/<name>/` asset route; `:static` leaves root-absolute image
    paths alone, for a site whose images live in `priv/static`
  * `:image_url` - `{module, function}` called as `function(url, use)` for
    each image the collection serves itself, answering the URL to serve
    instead: a smaller copy the host has built, say. `use` is `:page` for
    a picture on the page itself (in the body, or a post's cover) and
    `:card` for a post's picture on the blog index. See `image_url/3`

# `relabel_pills`

```elixir
@spec relabel_pills(String.t() | nil, %{
  optional(String.t()) =&gt; {String.t(), String.t()}
}) ::
  String.t() | nil
```

Re-labels pills that `apply_changelog_pills/1` rendered as neutral `other`.

The one seam a translated pill can use. `apply_changelog_pills/1` runs inside
the cache with English labels, so a host cannot translate there; this runs on
the way out, per request, and takes `%{"tag" => {class_suffix, label}}` with
the label already translated.

Both spellings are handled: a marker that reached the cache is already a
neutral `<span>`, while one written after the fact is still `[Tag]` — the
roadmap has had both, and handling only the first left `[Beta]` printed
verbatim in the middle of a heading.

# `reload`

```elixir
@spec reload() :: :ok
```

Clears all cached content so the next call re-reads from disk.

# `roadmap_html`

```elixir
@spec roadmap_html() :: String.t() | nil
```

Returns the rendered roadmap HTML, or `nil` when the roadmap path is
not configured or the file doesn't exist.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
