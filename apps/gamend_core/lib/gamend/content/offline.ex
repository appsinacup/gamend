defmodule Gamend.Content.Offline do
  @moduledoc """
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
      this site (`/admin/config`) is made absolute, since the file has no site
      of its own to be relative to.
    * An `<img>` on this site is written in as a `data:` URI, whether the
      collection serves it or, with `assets: :static`, the site's static files
      do. A video is too big for that and stays a link.
    * A mermaid diagram stays its source. Drawing it takes a script several
      times the size of the guides.
  """

  alias Gamend.Content
  alias Gamend.Content.Markdown

  @type option ::
          {:title, String.t()}
          | {:index_path, String.t()}
          | {:item_path, String.t()}
          | {:origin, String.t()}
          | {:static_file, (String.t() -> Path.t() | nil)}

  # In the file because nothing else can be: a page opened from disk has no
  # stylesheet to fetch. `screen` on the dark palette, or a PDF printed from a
  # dark desktop comes out as pale text on white paper.
  @stylesheet """
  :root { --bg: #fff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --code: #f6f8fa; --accent: #0b5cc4;
    --keyword: #7a1fd1; --string: #0f6b36; --number: #a34400; --type: #00666b; }
  @media screen and (prefers-color-scheme: dark) {
    :root { color-scheme: dark; --bg: #16181d; --fg: #e6e8eb; --muted: #a3acb8; --line: #363b45; --code: #21252c; --accent: #79b0ff;
      --keyword: #d2a8ff; --string: #7ee2a0; --number: #ffb27a; --type: #6fd8dd; }
  }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.7 system-ui, sans-serif; }
  a { color: var(--accent); }
  main { max-width: 48rem; margin: 0 auto; padding: 0 1rem 4rem; }
  #contents { padding: 1rem; font-size: 14px; }
  #contents ul { list-style: none; margin: 0; padding: 0; }
  #contents ul ul { padding-left: 1rem; }
  #contents li { margin: .25rem 0; }
  #contents .category { font-weight: 600; }
  .site { font-size: 18px; font-weight: 700; margin: 0; }
  .source, .to-contents { color: var(--muted); font-size: 14px; }
  article { border-top: 1px solid var(--line); margin-top: 3rem; }
  h1 { font-size: 30px; line-height: 1.25; margin: 2rem 0 .5rem; }
  h2 { font-size: 22px; margin-top: 2.5rem; }
  h3 { font-size: 18px; margin-top: 2rem; }
  img { max-width: 100%; height: auto; }
  code, pre { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 14px; }
  code { background: var(--code); border-radius: 4px; padding: .1em .3em; }
  pre { background: var(--code); border-radius: 8px; overflow-x: auto; padding: .75rem 1rem; line-height: 1.5; }
  pre code { background: none; padding: 0; }
  blockquote { border-left: 4px solid var(--line); color: var(--muted); margin-left: 0; padding-left: 1rem; }
  table { border-collapse: collapse; display: block; overflow-x: auto; }
  th, td { border: 1px solid var(--line); padding: .4rem .6rem; text-align: left; vertical-align: top; }
  .admonition { background: var(--code); border-left: 4px solid var(--accent); border-radius: 4px; margin: 1rem 0; padding: .5rem 1rem; }
  .admonition-title { font-weight: 600; margin: 0 0 .25rem; }
  [class*="l-comment"] { color: var(--muted); font-style: italic; }
  [class*="l-keyword"] { color: var(--keyword); }
  [class*="l-string"] { color: var(--string); }
  [class*="l-number"], [class*="l-boolean"], [class*="l-constant"] { color: var(--number); }
  [class*="l-function"], [class*="l-constructor"] { color: var(--accent); }
  [class*="l-type"], [class*="l-module"], [class*="l-namespace"] { color: var(--type); }
  @media screen and (min-width: 64rem) {
    body { padding-left: 20rem; }
    #contents { position: fixed; inset: 0 auto 0 0; width: 20rem; box-sizing: border-box; overflow-y: auto; border-right: 1px solid var(--line); }
    .to-contents { display: none; }
  }
  @media print {
    #contents { break-after: page; }
    article { border: 0; break-before: page; }
    .to-contents { display: none; }
    pre { white-space: pre-wrap; }
  }
  """

  @doc """
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
  """
  @spec html(atom(), [option()]) :: String.t() | nil
  def html(collection, opts) when is_atom(collection) do
    case Content.list_docs(collection) do
      [] ->
        nil

      docs ->
        Content.memoize({__MODULE__, collection, opts, Enum.map(docs, & &1.slug)}, fn ->
          build(collection, docs, Map.new(opts))
        end)
    end
  end

  defp build(collection, docs, opts) do
    context = %{
      collection: collection,
      slugs: MapSet.new(docs, & &1.slug),
      index_path: opts.index_path,
      item_path: opts.item_path,
      origin: opts.origin,
      static_file: Map.get(opts, :static_file, fn _url -> nil end)
    }

    title = Markdown.escape(opts.title)
    source = opts.origin <> opts.index_path

    IO.iodata_to_binary([
      ~s(<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n),
      ~s(<meta name="viewport" content="width=device-width, initial-scale=1">\n),
      "<title>",
      title,
      "</title>\n<style>\n",
      @stylesheet,
      "</style>\n</head>\n<body>\n",
      ~s(<nav id="contents" aria-label="Contents">\n<p class="site">),
      title,
      ~s(</p>\n<p class="source">Offline copy of <a href="),
      Markdown.escape(source),
      ~s(">),
      Markdown.escape(source),
      "</a></p>\n",
      contents(Content.doc_tree(collection)),
      "</nav>\n<main>\n",
      Enum.map(docs, &article(&1, context)),
      "</main>\n</body>\n</html>\n"
    ])
  end

  defp contents(entries) do
    ["<ul>", Enum.map(entries, &contents_entry/1), "</ul>\n"]
  end

  defp contents_entry(%{type: :doc} = doc) do
    ["<li>", contents_link(doc.slug, doc.label), "</li>"]
  end

  defp contents_entry(%{type: :category, index: nil} = category) do
    ["<li><span class=\"category\">", Markdown.escape(category.label), "</span>"] ++
      [contents(category.children), "</li>"]
  end

  defp contents_entry(%{type: :category, index: index} = category) do
    ["<li>", contents_link(index.slug, category.label), contents(category.children), "</li>"]
  end

  defp contents_link(slug, label) do
    [~s(<a href="#), anchor(slug), ~s(">), Markdown.escape(label), "</a>"]
  end

  defp article(doc, context) do
    id = anchor(doc.slug)

    [
      ~s(<article id="#{id}">\n<h1>),
      Markdown.escape(doc.title),
      ~s(</h1>\n<p class="to-contents"><a href="#contents">Contents</a></p>\n),
      context.collection |> Content.doc_html(doc.slug) |> self_contained(id, context),
      "</article>\n"
    ]
  end

  # The raw slug, `/` and all: ids may hold one, and replacing it would let
  # `a/b` and `a-b` collide.
  defp anchor(slug), do: "doc-" <> Markdown.escape(slug)

  defp self_contained(nil, _anchor, _context), do: ""

  # Tags only. The sanitiser leaves `"` bare in text, so a pattern for
  # `id="…"` alone would also rewrite the HTML in a guide's code samples,
  # where every `<` is escaped and no tag can match.
  defp self_contained(html, anchor, context) do
    context = Map.put(context, :anchor, anchor)

    Regex.replace(~r/<[a-zA-Z][^<>]*>/, readable_diagrams(html), fn tag ->
      Regex.replace(~r/\s(id|href|src|poster)="([^"]*)"/, tag, fn _full, name, value ->
        ~s( #{name}="#{attribute(tag, name, value, context)}")
      end)
    end)
  end

  # First, and on its own: a diagram's source sits in an attribute, where the
  # sanitiser leaves `>` bare (`A --> B`) and no tag pattern would stop at the
  # right one.
  defp readable_diagrams(html) do
    Regex.replace(~r/<div\b[^>]*\bdata-diagram="([^"]*)"[^>]*><\/div>/, html, fn _full, source ->
      "<pre><code>#{source |> String.replace("<", "&lt;") |> String.replace(">", "&gt;")}</code></pre>"
    end)
  end

  defp attribute(_tag, "id", value, context), do: "#{context.anchor}--#{value}"
  defp attribute(_tag, _name, "//" <> _ = url, _context), do: url
  defp attribute(_tag, "href", "#" <> fragment, context), do: "##{context.anchor}--#{fragment}"
  defp attribute(_tag, "href", "/" <> _ = url, context), do: link(url, context)
  defp attribute("<img" <> _, "src", "/" <> _ = url, context), do: embed(url, context)
  defp attribute(_tag, _name, "/" <> _ = url, context), do: context.origin <> url
  defp attribute(_tag, _name, value, _context), do: value

  defp link(url, context) do
    [path | fragment] = String.split(url, "#", parts: 2)
    slug = String.replace_prefix(path, context.item_path <> "/", "")

    cond do
      path == context.index_path -> "#contents"
      MapSet.member?(context.slugs, slug) -> "#" <> Enum.join([anchor(slug) | fragment], "--")
      true -> context.origin <> url
    end
  end

  defp embed(url, context) do
    with path when is_binary(path) <- image_file(url, context),
         {:ok, bytes} <- File.read(path) do
      "data:#{MIME.from_path(path)};base64,#{Base.encode64(bytes)}"
    else
      _unreadable -> context.origin <> url
    end
  end

  defp image_file(url, context) do
    case String.split(url, "/content/#{context.collection}/", parts: 2) do
      ["", relative] -> Content.asset_path(context.collection, URI.decode(relative))
      _elsewhere -> context.static_file.(url)
    end
  end
end
