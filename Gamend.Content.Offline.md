# `Gamend.Content.Offline`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/content/offline.ex#L1)

A guide collection as one HTML file that needs no server.

A contents list, then every guide in reading order. The styles and images
are in the file, so it opens from disk, finds a word anywhere in the manual
and prints to a PDF. `GamendWeb.DocsLive` serves it; any collection can.

Built from `Gamend.Content.doc_html/2` rather than the markdown, so a host's
`:post_render` applies, and from `Gamend.Content.list_docs/1`, so a guide
`:visible` hides on the site is not in the file either.

## One page from many

A guide is written to be its own page, which stops being true here:

  * Headings repeat between guides (every other one has an "Overview"), so
    every id is namespaced by its guide, and a `#fragment` link with it.
  * A link to another guide goes to that guide's section. Any other link to
    this site (`/admin/settings`) is made absolute, since the file has no site
    of its own to be relative to.
  * An `<img>` on this site is written in as a `data:` URI, whether the
    collection serves it or, with `assets: :static`, the site's static files
    do. A video is too big for that and stays a link.
  * A mermaid diagram stays its source. Drawing it takes a script several
    times the size of the guides.

# `option`

```elixir
@type option() ::
  {:title, String.t()}
  | {:index_path, String.t()}
  | {:item_path, String.t()}
  | {:origin, String.t()}
  | {:static_file, (String.t() -&gt; Path.t() | nil)}
```

# `html`

```elixir
@spec html(atom(), [option()]) :: String.t() | nil
```

The whole collection as one HTML document, or `nil` when it has no guides.

Options, all required:

  * `:title` — the document's title
  * `:index_path` — the collection's index on the site, which a guide's link
    to it becomes a link to the contents
  * `:item_path` — the prefix of a guide's URL on the site
  * `:origin` — the site's URL, for every other link to it

With `:static_file`, a function answering which file on disk a URL path is
served from, an image outside the collection is written in too. Without it,
such an image is a link to the site.

Cached until `Gamend.Content.reload/0`, under the guides it holds: `:visible`
is decided per call, and a switch flipped at runtime has to reach a file
built before it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
