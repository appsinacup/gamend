defmodule Gamend.Content.Markdown do
  @moduledoc """
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
  """

  alias Gamend.Content.Frontmatter

  @typedoc """
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
  * `:image_url` — given each image's URL once it is resolved (never an
    `http` or `data:` one), answers the URL to serve instead: a smaller copy
    the host has built, say. `Gamend.Content` passes the collection's
    registered `:image_url` here
  """
  @type opt ::
          {:collection, String.t()}
          | {:assets, :content | :static}
          | {:dir, String.t()}
          | {:base_path, String.t() | nil}
          | {:slug, String.t() | nil}
          | {:index, boolean()}
          | {:id, String.t()}
          | {:image_url, (String.t() -> String.t()) | nil}

  @admonitions ~w(note tip info warning danger caution important)

  # The highlighter ships no GDScript grammar, so a ```gdscript block renders
  # as flat text. JavaScript's grammar colours its keywords, strings and calls
  # closely enough; the markdown keeps saying gdscript, which is what a reader
  # should see.
  @language_aliases %{
    "gdscript" => "javascript",
    "gd" => "javascript",
    "godot" => "javascript"
  }

  @doc "Render a file, or `nil` when it cannot be read or parsed."
  @spec render_file(Path.t(), [opt()]) :: String.t() | nil
  def render_file(path, opts \\ []) do
    opts = Keyword.put_new(opts, :index, Path.rootname(Path.basename(path)) == "index")

    case File.read(path) do
      {:ok, content} ->
        case render(content, opts) do
          {:ok, html} -> html
          {:error, _reason} -> nil
        end

      _unreadable ->
        nil
    end
  end

  @doc "Render markdown source. The frontmatter, if any, is dropped."
  @spec render(String.t(), [opt()]) :: {:ok, String.t()} | {:error, term()}
  def render(content, opts \\ []) when is_binary(content) do
    source =
      content
      |> Frontmatter.body()
      |> fix_table_separators()

    with {:ok, document} <- MDEx.parse_document(source, options()),
         {:ok, html} <- document |> transform(opts) |> MDEx.to_html(options()) do
      {:ok, html |> drop_heading_anchors() |> rewrite_images(opts)}
    end
  end

  # `header_id_prefix` gives every heading an id AND an empty
  # `<a class="anchor">` inside it. The id is what a `#section` link and the
  # table of contents point at; the link draws nothing (no stylesheet styles
  # it) yet sits in the tab order with no name, which a screen reader reads
  # as "link" (axe `link-name`, Lighthouse 2026-10-08). So it goes.
  @doc false
  def drop_heading_anchors(html) do
    String.replace(html, ~r{<a\b[^>]*\bclass="anchor"[^>]*>\s*</a>}, "")
  end

  defp transform(document, opts) do
    document
    |> alias_code_languages()
    |> lift_mermaid(Keyword.get(opts, :id, "md"))
    |> unify_admonitions()
    |> rewrite_links(opts)
  end

  @doc """
  The headings of rendered HTML, for a table of contents: `h2` and `h3`
  with their ids and plain text.

  Read from the HTML because that is what the cache holds; the renderer
  puts the id first on the heading tag, so the pattern is stable.
  """
  @spec toc(String.t() | nil) :: [%{id: String.t(), text: String.t(), level: 2 | 3}]
  def toc(nil), do: []

  def toc(html) do
    ~r/<h([23]) id="([^"]+)">(.*?)<\/h\1>/s
    |> Regex.scan(html)
    |> Enum.map(fn [_, level, id, inner] ->
      %{id: id, text: plain_text(inner), level: String.to_integer(level)}
    end)
  end

  @doc """
  The `h2` and `h3` sections of rendered HTML: each heading as `toc/1` gives
  it, plus `:lede`, the first sentence of the paragraph that opens the
  section, or nil when the section opens with a list, a table or code.
  """
  @spec sections(String.t() | nil) :: [
          %{id: String.t(), text: String.t(), level: 2 | 3, lede: String.t() | nil}
        ]
  def sections(nil), do: []

  def sections(html) do
    headings = Regex.scan(~r/<h([23]) id="([^"]+)">(.*?)<\/h\1>/s, html, return: :index)
    starts = Enum.map(headings, fn [{start, _length} | _groups] -> start end)
    # Each section runs to the next heading, the last to the end of the page.
    ends = starts |> Enum.drop(1) |> Enum.concat([byte_size(html)])

    headings
    |> Enum.zip(ends)
    |> Enum.map(fn {[{start, length}, level, id, inner], stop} ->
      body = binary_part(html, start + length, stop - start - length)

      %{
        id: slice(html, id),
        text: html |> slice(inner) |> plain_text() |> decode_entities(),
        level: html |> slice(level) |> String.to_integer(),
        lede: lede(body)
      }
    end)
  end

  defp slice(html, {start, length}), do: binary_part(html, start, length)

  # The opening paragraph only: a section that starts with a list or a code
  # block has no sentence to offer.
  defp lede(body) do
    with [_all, inner] <- Regex.run(~r/\A\s*<p>(.*?)<\/p>/s, body),
         text when text != "" <- inner |> plain_text() |> decode_entities() do
      text |> String.split(~r/(?<=[.!?])\s+/, parts: 2) |> hd()
    else
      _ -> nil
    end
  end

  defp decode_entities(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  @doc """
  The first picture in a markdown body, at the URL the rendered page serves it
  from (`image_src/2`, before any `:image_url`), or nil.

  A markdown image or an `<img>` written in raw HTML, whichever comes first;
  one inside a code block is code, not a picture. For a card that has only
  the post itself to take a picture from. Give it the body, after the
  frontmatter.
  """
  @spec first_image(String.t(), [opt()]) :: String.t() | nil
  def first_image(body, opts \\ []) when is_binary(body) do
    case MDEx.parse_document(body, options()) do
      {:ok, document} ->
        document
        |> Enum.find_value(fn
          %MDEx.Image{url: url} when url != "" -> url
          %MDEx.HtmlBlock{literal: html} -> html_image(html)
          %MDEx.HtmlInline{literal: html} -> html_image(html)
          _node -> nil
        end)
        |> then(&(&1 && image_src(&1, opts)))

      {:error, _reason} ->
        nil
    end
  end

  defp html_image(html) do
    case Regex.run(~r/<img\b[^>]*\ssrc="([^"]+)"/, html) do
      [_, src] -> src
      nil -> nil
    end
  end

  @doc """
  Drop a leading `<h1>`: the page renders the title itself, so leaving it in
  prints it twice. Attribute-tolerant, because headings carry ids now.
  """
  @spec strip_first_h1(String.t()) :: String.t()
  def strip_first_h1(html) do
    Regex.replace(~r/\A\s*<h1\b[^>]*>.*?<\/h1>\s*/s, html, "", global: false)
  end

  @doc "Inline markup removed, entities left as they are."
  @spec plain_text(String.t()) :: String.t()
  def plain_text(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  ## Options

  defp options do
    [
      extension: [
        autolink: true,
        strikethrough: true,
        table: true,
        tasklist: true,
        footnotes: true,
        # Headings get ids, so a table of contents and a `#section` link both
        # have something to point at.
        header_id_prefix: "",
        alerts: true,
        block_directive: true,
        multiline_block_quotes: true
      ],
      parse: [smart: false],
      # Raw HTML reaches the sanitiser rather than being dropped before it.
      render: [unsafe: true],
      # Linked rather than inline: the formatter emits token classes and the
      # colours live in app.css, so the same markup reads correctly in both
      # the light and dark themes. Inline styles would pin one palette.
      syntax_highlight: [engine: :lumis, opts: [formatter: :html_linked]],
      sanitize: sanitize_options()
    ]
  end

  # The default allowlist keeps the highlighter's classes and the language
  # hint; what is added is the small vocabulary of a technical guide.
  defp sanitize_options do
    MDEx.Document.default_sanitize_options()
    |> Keyword.merge(
      add_tags:
        ~w(figure figcaption video source details summary div span kbd svg path g circle rect line polyline polygon),
      add_generic_attributes: ~w(class id aria-hidden),
      add_tag_attributes: %{
        "video" => ~w(controls muted loop playsinline preload poster width height autoplay),
        "source" => ~w(src type),
        "img" => ~w(loading decoding width height),
        "svg" => ~w(viewBox xmlns fill width height stroke stroke-width),
        "path" => ~w(d fill stroke stroke-width opacity fill-rule),
        "g" => ~w(fill stroke opacity transform),
        "circle" => ~w(cx cy r fill stroke),
        "rect" => ~w(x y width height rx fill stroke),
        "line" => ~w(x1 y1 x2 y2 stroke),
        "polyline" => ~w(points fill stroke),
        "polygon" => ~w(points fill stroke),
        "details" => ~w(open),
        # The diagram element `lift_mermaid/2` emits is sanitised with the
        # rest of the page, so its source attribute is allowed on a `<div>`.
        "div" => ~w(data-diagram)
      },
      # Its hook attributes too, but only with the one hook and the one
      # update mode the diagram uses: a pasted `<div phx-hook="…">` naming
      # any other hook is still stripped.
      add_tag_attribute_values: %{
        "div" => %{"phx-hook" => ["MermaidDiagram"], "phx-update" => ["ignore"]}
      }
    )
  end

  ## Source

  # Markdown tables require separator rows to match the header row exactly.
  # This helper scans for pipe-table patterns and adjusts separator rows.
  defp fix_table_separators(content) do
    content
    |> String.split("\n")
    |> fix_table_lines([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp fix_table_lines([], acc), do: acc

  defp fix_table_lines([header, sep | rest], acc) do
    if table_header?(header) and table_separator?(sep) do
      col_count = count_table_columns(header)
      fixed_sep = build_separator(col_count)
      fix_table_lines(rest, [fixed_sep, header | acc])
    else
      fix_table_lines([sep | rest], [header | acc])
    end
  end

  defp fix_table_lines([line], acc), do: [line | acc]

  defp table_header?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "|") and String.contains?(trimmed, "|")
  end

  defp table_separator?(line) do
    trimmed = String.trim(line)
    String.starts_with?(trimmed, "|") and Regex.match?(~r/^\|[\s\-:|]+\|$/, trimmed)
  end

  defp count_table_columns(line) do
    line
    |> String.trim()
    |> String.trim("|")
    |> String.split("|")
    |> length()
  end

  defp build_separator(col_count) do
    cells = List.duplicate("-", col_count) |> Enum.join("|")
    "|#{cells}|"
  end

  ## Tree

  # A fence's language hint is the code block's `info`.
  defp alias_code_languages(document) do
    MDEx.Document.update_nodes(document, MDEx.CodeBlock, fn %{info: info} = block ->
      case Map.fetch(@language_aliases, String.downcase(info)) do
        {:ok, language} -> %{block | info: language}
        :error -> block
      end
    end)
  end

  # A mermaid fence is a diagram, not code: the highlighter would wrap every
  # line in spans and the hook needs the text whole. Each becomes the hook's
  # element, numbered in document order, wherever the fence sits — inside a
  # list item or an admonition as much as at the top level.
  defp lift_mermaid(document, prefix) do
    {document, _count} =
      MDEx.traverse_and_update(document, 0, fn
        %MDEx.CodeBlock{info: "mermaid", literal: source}, index ->
          {%MDEx.Raw{literal: diagram(prefix, index, source)}, index + 1}

        node, index ->
          {node, index}
      end)

    document
  end

  defp diagram(prefix, index, source) do
    ~s(<div id="#{escape(prefix)}-mermaid-#{index}" class="mermaid-diagram" phx-hook="MermaidDiagram" phx-update="ignore" data-diagram="#{escape(String.trim(source))}"></div>)
  end

  # Both spellings become one directive (see the moduledoc). A directive of
  # another kind — `:::columns` — is not an admonition and is left alone.
  defp unify_admonitions(document) do
    MDEx.traverse_and_update(document, fn
      %MDEx.Alert{alert_type: kind, title: title, nodes: nodes} ->
        admonition(Atom.to_string(kind), title, nodes)

      %MDEx.BlockDirective{info: info, nodes: nodes} = directive ->
        case Regex.run(~r/^(\w+)(?:\[([^\]]*)\])?$/, info) do
          [_, kind] when kind in @admonitions -> admonition(kind, nil, nodes)
          [_, kind, title] when kind in @admonitions -> admonition(kind, title, nodes)
          _other -> directive
        end

      node ->
        node
    end)
  end

  # Rendered as `<div class="#{info}">`, so the class list is the info. The
  # title is a raw block so it carries its class; the children follow it in
  # the tree, still nodes, so a link or a fence inside is rewritten with the
  # rest.
  defp admonition(kind, title, nodes) do
    title = if title in [nil, ""], do: label(kind), else: title

    %MDEx.BlockDirective{
      info: "admonition admonition-#{kind}",
      nodes: [
        %MDEx.HtmlBlock{literal: ~s(<p class="admonition-title">#{escape(title)}</p>)} | nodes
      ]
    }
  end

  defp label("tip"), do: "Tip"
  defp label("info"), do: "Info"
  defp label("warning"), do: "Warning"
  defp label("danger"), do: "Danger"
  defp label("caution"), do: "Caution"
  defp label("important"), do: "Important"
  defp label(_note), do: "Note"

  # `[Principles](./principles.md)` and `(../reference/index.md#anchor)` are
  # how a guide points at its neighbours, and how an editor previews them.
  # Resolved against the document's own folder — order prefixes stripped, an
  # `index` file meaning its folder — and rewritten to the route. A page's
  # folder is its slug's parent; an index page's slug already names its
  # folder, so taking the parent there sent `builds.md` in `forge/index.md`
  # to `/docs/builds`.
  defp rewrite_links(document, opts) do
    case Keyword.get(opts, :base_path) do
      nil ->
        document

      base ->
        slug = Keyword.get(opts, :slug) || ""

        slug_dir =
          if Keyword.get(opts, :index, false),
            do: slug,
            else: slug |> Path.dirname() |> normalize_dir()

        MDEx.Document.update_nodes(document, MDEx.Link, fn %{url: url} = link ->
          case rewrite_md_link(url, slug_dir, base) do
            nil -> link
            route -> %{link | url: route}
          end
        end)
    end
  end

  defp normalize_dir("."), do: ""
  defp normalize_dir(dir), do: dir

  defp rewrite_md_link(href, slug_dir, base) do
    {path, fragment} =
      case String.split(href, "#", parts: 2) do
        [p, f] -> {p, "#" <> f}
        [p] -> {p, ""}
      end

    if relative_markdown?(path) do
      # Walked with the slug's segments innermost-first, so `..` is a drop
      # and a segment is a prepend; reversed back at the end.
      slug =
        path
        |> String.replace(~r/\.mdx?$/, "")
        |> Path.split()
        |> Enum.reduce(slug_dir |> Path.split() |> Enum.reverse(), fn
          ".", acc -> acc
          "..", acc -> Enum.drop(acc, 1)
          "index", acc -> acc
          segment, acc -> [strip_order_prefix(segment) | acc]
        end)
        |> Enum.reverse()
        |> Enum.join("/")

      String.trim_trailing(base, "/") <> "/" <> slug <> fragment
    end
  end

  defp relative_markdown?(path) do
    Regex.match?(~r/\.mdx?$/, path) and not String.starts_with?(path, ["/", "http", "mailto:"])
  end

  ## HTML

  # Every image's `src` through `image_src/2`, then the host's `:image_url`,
  # with the same lazy-loading attributes.
  #
  # On the HTML rather than the tree, on purpose: a raw `<figure>` holds an
  # `<img>` that is no `MDEx.Image`, and this way every image, written either
  # way, gets the same path and the same attributes. Also handles `<image>`
  # tags (non-standard HTML) by converting them to `<img>`. External URLs
  # (`http…`, `data:`) are left exactly as written.
  defp rewrite_images(html, opts) do
    swap = Keyword.get(opts, :image_url) || (& &1)
    html = Regex.replace(~r/<image\b/, html, "<img")

    Regex.replace(
      ~r/<img([^>]*)\ssrc="([^"]+)"([^>]*)>/,
      html,
      fn full, before, src, after_attr ->
        if external?(src) do
          full
        else
          url = src |> image_src(opts) |> swap.()

          add_lazy_image_attrs(~s(<img#{before} src="#{url}"#{after_attr}>))
        end
      end
    )
  end

  @doc """
  The URL an image written in a collection's markdown is served from.

  Points it at `/content/<collection>/…`, the host content asset route, in
  the three ways authors write it:

    1. Relative:      `gamend/auth.png`       → `/content/blog/gamend/auth.png`
    2. Absolute:      `/gamend/auth.png`      → `/content/blog/gamend/auth.png`
    3. Type-prefixed: `/blog/gamend/auth.png` → `/content/blog/gamend/auth.png`

  With `assets: :static`, an absolute path is a URL the host serves and is
  left alone; only relative ones are resolved, against the file's folder
  (`:dir`). External URLs (`http…`, `data:`) and paths already under
  `/content/` come back as they are.
  """
  @spec image_src(String.t(), [opt()]) :: String.t()
  def image_src(src, opts \\ []) when is_binary(src) do
    collection = Keyword.get(opts, :collection, "docs")
    mode = Keyword.get(opts, :assets, :content)
    dir = opts |> Keyword.get(:dir, "") |> normalize_dir()

    cond do
      external?(src) or String.starts_with?(src, "/content/") ->
        src

      mode == :static and String.starts_with?(src, "/") ->
        src

      true ->
        clean =
          src
          |> String.trim_leading("/")
          |> String.trim_leading("./")
          # Strip redundant type prefix (e.g. "blog/" from "/blog/gamend/img.png")
          |> strip_content_type_prefix(collection)
          |> prefix_dir(mode, dir)

        "/content/#{collection}/#{clean}"
    end
  end

  @doc false
  # Not served by this site: left as written, and never handed to a host's
  # `:image_url`.
  def external?(src), do: String.starts_with?(src, ["http", "data:"])

  # A relative path in a nested guide is relative to that guide's folder, so
  # `../shared/x.png` from `10-manual/20-scenes.md` is `shared/x.png`.
  defp prefix_dir(path, :static, dir) when dir != "" do
    Path.join(dir, path) |> Path.expand("/") |> String.trim_leading("/")
  end

  defp prefix_dir(path, _mode, _dir), do: path

  defp add_lazy_image_attrs(tag) do
    tag
    |> ensure_image_attr("loading", "lazy")
    |> ensure_image_attr("decoding", "async")
  end

  defp ensure_image_attr(tag, attr, value) do
    if Regex.match?(~r/\s#{Regex.escape(attr)}=/, tag) do
      tag
    else
      String.replace(tag, ~r/<img\b/, ~s(<img #{attr}="#{value}"), global: false)
    end
  end

  defp strip_content_type_prefix(path, content_type) do
    prefix = content_type <> "/"

    if String.starts_with?(path, prefix) do
      String.trim_leading(path, prefix)
    else
      path
    end
  end

  # "20-deployment" -> "deployment". Ordering lives in the filename so the
  # tree reads in the same order it renders.
  @doc false
  def strip_order_prefix(name), do: Regex.replace(~r/^\d+[-_]/, name, "")

  # Core does not depend on Phoenix.HTML; the five characters an attribute
  # value or a text node has to escape are these.
  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
