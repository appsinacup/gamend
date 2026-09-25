defmodule Gamend.Content do
  @moduledoc """
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
  """

  alias Gamend.Content.Frontmatter
  alias Gamend.Content.Markdown
  alias Gamend.Content.Tree

  # Heroicon names; the docs page falls back to these when a file names none.
  @default_doc_icon "hero-document-text"
  @default_category_icon "hero-folder"
  # A Tailwind text colour class; Tailwind sees it because priv/docs is a
  # scanned source.
  @default_category_color "text-primary"

  @cache_key {__MODULE__, :cache}
  @registered_paths_key {__MODULE__, :registered_paths}
  @default_content_config [
    changelog_candidates: ["CHANGELOG.md"],
    roadmap_candidates: ["ROADMAP.md"],
    blog_candidates: ["blog"]
  ]

  @doc """
  Clears all cached content so the next call re-reads from disk.
  """
  @spec reload() :: :ok
  def reload do
    :persistent_term.put(@cache_key, %{})
    :ok
  end

  @doc """
  Registers a named content source.

  Supported options:
    * `:kind` - `:file` or `:dir`
    * `:path` - single candidate path
    * `:candidates` - ordered candidate paths
    * `:asset_root` - `:self` or `:dirname` when serving assets
    * `:post_render` - `{module, function}` applied to rendered guide HTML
    * `:nesting` - `:flat` (the default: one folder level, slugs are file
      names) or `:tree` (any depth, slugs are paths; see `Gamend.Content.Tree`)
    * `:base_path` - the route prefix guides are served under, such as
      `"/docs"`. With it set, a link written to a neighbouring `.md` file is
      rewritten to that guide's route
    * `:assets` - `:content` (the default) serves images through the
      `/content/<name>/` asset route; `:static` leaves root-absolute image
      paths alone, for a site whose images live in `priv/static`
  """
  @spec register_path(atom() | String.t(), keyword()) :: :ok
  def register_path(name, opts) when is_atom(name) or is_binary(name) do
    normalized_name = normalize_registered_name(name)
    entry = normalize_registered_entry!(opts)

    :persistent_term.put(
      @registered_paths_key,
      Map.put(registered_path_overrides(), normalized_name, entry)
    )

    reload()
  end

  @doc false
  # For tests: forget a registration made with `register_path/2`.
  @spec unregister_path(atom() | String.t()) :: :ok
  def unregister_path(name) do
    :persistent_term.put(
      @registered_paths_key,
      Map.delete(registered_path_overrides(), normalize_registered_name(name))
    )

    reload()
  end

  @doc """
  Returns the resolved absolute path for a registered content source, or `nil`.
  """
  @spec path(atom() | String.t()) :: String.t() | nil
  def path(name) when is_atom(name) or is_binary(name) do
    case Map.get(registered_paths(), normalize_registered_name(name)) do
      %{kind: :file, candidates: candidates} -> find_existing_file(candidates)
      %{kind: :dir, candidates: candidates} -> find_existing_dir(candidates)
      nil -> nil
    end
  end

  @doc """
  Returns the absolute path for an asset relative to a registered content
  source. Returns `nil` when not found or path traversal is attempted.
  """
  @spec asset_path(atom() | String.t(), String.t()) :: String.t() | nil
  def asset_path(name, relative) when is_atom(name) or is_binary(name) do
    case {Map.get(registered_paths(), normalize_registered_name(name)), path(name)} do
      {nil, _resolved_path} ->
        nil

      {%{asset_root: :self}, resolved_path} ->
        serve_asset(resolved_path, relative)

      {%{asset_root: :dirname}, nil} ->
        nil

      {%{asset_root: :dirname}, resolved_path} ->
        serve_asset(Path.dirname(resolved_path), relative)

      {_entry, _resolved_path} ->
        nil
    end
  end

  defp get_cache, do: :persistent_term.get(@cache_key, %{})

  # Cache helper that only stores non-nil, non-empty results.
  # Transient file-read failures therefore cause a cache miss on
  # the current request but don't poison subsequent ones.
  defp cached(key, fun) do
    cache = get_cache()

    case Map.fetch(cache, key) do
      {:ok, value} ->
        value

      :error ->
        value = fun.()

        if cacheable?(value) do
          :persistent_term.put(@cache_key, Map.put(get_cache(), key, value))
        end

        value
    end
  end

  defp cacheable?(nil), do: false
  defp cacheable?([]), do: false
  defp cacheable?(_), do: true

  # ---------------------------------------------------------------------------
  # Changelog
  # ---------------------------------------------------------------------------

  @doc """
  Returns the rendered changelog HTML, or `nil` when the changelog path is
  not configured or the file doesn't exist.
  """
  @spec changelog_html() :: String.t() | nil
  def changelog_html do
    cached(:changelog_html, fn ->
      case path(:changelog) do
        nil ->
          nil

        path ->
          case render_markdown_file(path, "changelog") do
            nil -> nil
            html -> apply_changelog_pills(html)
          end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Roadmap
  # ---------------------------------------------------------------------------

  @doc """
  Returns the rendered roadmap HTML, or `nil` when the roadmap path is
  not configured or the file doesn't exist.
  """
  @spec roadmap_html() :: String.t() | nil
  def roadmap_html do
    cached(:roadmap_html, fn ->
      case path(:roadmap) do
        nil ->
          nil

        path ->
          case render_markdown_file(path, "roadmap") do
            nil -> nil
            html -> apply_changelog_pills(html)
          end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Docs
  # ---------------------------------------------------------------------------

  @doc """
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
  """
  @spec list_doc_categories(atom()) :: [%{category: String.t() | nil, guides: [map()]}]
  def list_doc_categories(collection \\ :docs) when is_atom(collection) do
    cached({:doc_categories, collection}, fn ->
      case {path(collection), nesting(collection)} do
        {nil, _nesting} -> []
        {dir, :flat} -> flat_categories(dir)
        {_dir, :tree} -> tree_categories(doc_tree(collection))
      end
    end)
  end

  defp flat_categories(dir) do
    dir
    |> Path.join("*/*.md")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "_category.md"))
    |> Enum.sort()
    |> Enum.map(&parse_doc(&1, dir))
    |> Enum.chunk_by(& &1.category)
    |> Enum.map(fn [%{category: folder} | _] = guides ->
      dir |> category_meta(folder) |> Map.put(:guides, guides)
    end)
  end

  defp tree_categories(tree) do
    {root_docs, categories} = Enum.split_with(tree, &(&1.type == :doc))

    root =
      if root_docs == [],
        do: [],
        else: [
          %{
            category: nil,
            icon: @default_category_icon,
            color: @default_category_color,
            guides: root_docs
          }
        ]

    root ++
      Enum.map(categories, fn category ->
        %{
          category: category.title,
          icon: category.icon,
          color: category.color,
          guides: Tree.flatten([category])
        }
      end)
  end

  @doc """
  The whole tree of a `nesting: :tree` collection — categories with their
  children, guides with their metadata — in reading order. A flat collection
  answers its categories as top-level nodes, so a sidebar built from this
  works on either.
  """
  @spec doc_tree(atom()) :: [Tree.entry()]
  def doc_tree(collection \\ :docs) when is_atom(collection) do
    cached({:doc_tree, collection}, fn ->
      case {path(collection), nesting(collection)} do
        {nil, _nesting} ->
          []

        {dir, :tree} ->
          Tree.scan(dir,
            doc_icon: @default_doc_icon,
            category_icon: @default_category_icon,
            category_color: @default_category_color
          )

        {dir, :flat} ->
          dir
          |> flat_categories()
          |> Enum.map(fn category ->
            %{
              type: :category,
              slug: category.category,
              dir: "",
              title: category.category,
              label: category.category,
              icon: category.icon,
              color: category.color,
              description: nil,
              position: nil,
              collapsed: false,
              category: nil,
              index: nil,
              children: Enum.map(category.guides, &Map.put(&1, :type, :doc))
            }
          end)
      end
    end)
  end

  @doc """
  Every guide as a flat list, in reading order.

  For a flat collection that is the order of `list_doc_categories/1`. For a
  tree it is the tree's own order — a category's page, then its children,
  then the next sibling — which is what previous/next should follow and what
  the grouped view, with the root guides pulled to the front, does not.
  """
  @spec list_docs(atom()) :: [map()]
  def list_docs(collection \\ :docs) when is_atom(collection) do
    case nesting(collection) do
      :tree -> Tree.flatten(doc_tree(collection))
      :flat -> Enum.flat_map(list_doc_categories(collection), & &1.guides)
    end
  end

  @doc "Returns a single guide map by slug, or `nil`."
  @spec get_doc(atom(), String.t()) :: map() | nil
  def get_doc(collection \\ :docs, slug)

  def get_doc(collection, slug) when is_atom(collection) and is_binary(slug) do
    Enum.find(list_docs(collection), fn doc -> doc.slug == slug end)
  end

  def get_doc(_collection, _slug), do: nil

  @doc """
  A category of a tree collection by its slug, or `nil`. A category without
  an `index.md` has no guide of its own, and this is how its page is found.
  """
  @spec get_doc_category(atom(), String.t()) :: Tree.category() | nil
  def get_doc_category(collection \\ :docs, slug)

  def get_doc_category(collection, slug) when is_atom(collection) and is_binary(slug) do
    Tree.find_category(doc_tree(collection), slug)
  end

  def get_doc_category(_collection, _slug), do: nil

  @doc """
  The category a guide belongs to — its display title, icon and colour — or
  `nil`.

  Found by membership rather than by name: a guide carries its category's
  *folder* ("10-setup") while the category carries the display title ("Setup").
  Both pages that render a guide need this, so deriving it twice by hand was
  how the two drifted apart.

  In a tree collection this is the guide's nearest category, with its
  `guides` being that category's direct pages.
  """
  @spec doc_category(atom(), String.t()) :: map() | nil
  def doc_category(collection \\ :docs, slug)

  def doc_category(collection, slug) when is_atom(collection) and is_binary(slug) do
    case nesting(collection) do
      :flat ->
        Enum.find(list_doc_categories(collection), fn category ->
          Enum.any?(category.guides, &(&1.slug == slug))
        end)

      :tree ->
        tree = doc_tree(collection)

        with %{category: parent} when is_binary(parent) <- Tree.find_doc(tree, slug),
             %{} = category <- Tree.find_category(tree, parent) do
          %{
            category: category.title,
            slug: category.slug,
            icon: category.icon,
            color: category.color,
            guides: Enum.filter(category.children, &(&1.type == :doc))
          }
        else
          _ -> nil
        end
    end
  end

  def doc_category(_collection, _slug), do: nil

  @doc """
  The categories above a guide, outermost first, then the guide. For a
  breadcrumb. Empty in a flat collection, whose one level the index already
  shows.
  """
  @spec doc_breadcrumbs(atom(), String.t()) :: [Tree.entry()]
  def doc_breadcrumbs(collection \\ :docs, slug)

  def doc_breadcrumbs(collection, slug) when is_atom(collection) and is_binary(slug) do
    case nesting(collection) do
      :tree -> Tree.breadcrumbs(doc_tree(collection), slug)
      :flat -> []
    end
  end

  def doc_breadcrumbs(_collection, _slug), do: []

  @doc """
  `{previous, next}` guides around `slug` in reading order, either possibly
  `nil`.

  Across categories, not within one: the collections are written to be read
  front to back, and stopping at a category boundary would strand the reader on
  the last page of each section.
  """
  @spec doc_neighbours(atom(), String.t()) :: {map() | nil, map() | nil}
  def doc_neighbours(collection \\ :docs, slug)

  def doc_neighbours(collection, slug) when is_atom(collection) and is_binary(slug) do
    docs = list_docs(collection)

    case Enum.find_index(docs, &(&1.slug == slug)) do
      nil -> {nil, nil}
      0 -> {nil, Enum.at(docs, 1)}
      index -> {Enum.at(docs, index - 1), Enum.at(docs, index + 1)}
    end
  end

  def doc_neighbours(_collection, _slug), do: {nil, nil}

  @doc """
  Renders a guide's markdown to HTML, or `nil`.

  The leading `# ` heading is dropped: the page renders the title itself, so
  leaving it in would print it twice.

  A collection registered with `:post_render` runs that `{module, function}`
  over the finished HTML — the hook Polyglot Pirates' guide uses to turn
  `[coins:250]` into a badge. It runs *after* markdown rendering because the
  sanitiser strips raw HTML out of the markdown, and inside the cache because
  the result is as static as the markdown it came from.
  """
  @spec doc_html(atom(), String.t()) :: String.t() | nil
  def doc_html(collection \\ :docs, slug)

  def doc_html(collection, slug) when is_atom(collection) and is_binary(slug) do
    cached({:doc_html, collection, slug}, fn ->
      case get_doc(collection, slug) do
        nil ->
          nil

        doc ->
          entry = Map.get(registered_paths(), normalize_registered_name(collection), %{})

          doc.path
          |> Markdown.render_file(
            collection: Atom.to_string(collection),
            assets: Map.get(entry, :assets, :content),
            base_path: Map.get(entry, :base_path),
            slug: slug,
            dir: Map.get(doc, :dir, ""),
            id: "doc-" <> String.replace(slug, "/", "-")
          )
          |> case do
            nil -> nil
            html -> html |> Markdown.strip_first_h1() |> post_render(collection)
          end
      end
    end)
  end

  def doc_html(_collection, _slug), do: nil

  @doc "The headings of a rendered guide, for a table of contents."
  @spec doc_toc(atom(), String.t()) :: [%{id: String.t(), text: String.t(), level: 2 | 3}]
  def doc_toc(collection \\ :docs, slug), do: collection |> doc_html(slug) |> Markdown.toc()

  defp post_render(html, collection) do
    case Map.get(registered_paths(), normalize_registered_name(collection)) do
      %{post_render: {module, function}} -> apply(module, function, [html])
      _entry -> html
    end
  end

  defp nesting(collection) do
    case Map.get(registered_paths(), normalize_registered_name(collection)) do
      %{nesting: nesting} -> nesting
      _entry -> :flat
    end
  end

  defp parse_doc(path, root) do
    content = File.read!(path)
    {meta, body} = Frontmatter.parse(content)
    slug = path |> Path.basename(".md") |> strip_order_prefix()
    title = string(meta["title"]) || extract_title(body) || humanize_slug(slug)
    description = string(meta["description"])

    %{
      slug: slug,
      title: title,
      label: string(meta["sidebar_label"]) || string(meta["label"]) || title,
      summary: description || extract_excerpt(body),
      description: description,
      image: string(meta["image"]),
      keywords: Frontmatter.list(meta["keywords"]),
      icon: string(meta["icon"]) || @default_doc_icon,
      category: category_dir(path, root),
      dir: category_dir(path, root),
      path: path
    }
  end

  defp category_dir(path, root) do
    path |> Path.relative_to(root) |> Path.dirname()
  end

  # A folder's own `_category.md` names and illustrates the category. It is
  # optional: without one the folder name is humanised and the default icon
  # used, so a new category is still just a directory.
  defp category_meta(root, dir) do
    path = Path.join([root, dir, "_category.md"])

    meta = if File.exists?(path), do: Frontmatter.meta(File.read!(path)), else: %{}

    %{
      category: string(meta["title"]) || dir |> strip_order_prefix() |> humanize_slug(),
      icon: string(meta["icon"]) || @default_category_icon,
      color: string(meta["color"]) || @default_category_color
    }
  end

  @doc """
  Reads a leading `---` fenced block.

  Deliberately not YAML — see `Gamend.Content.Frontmatter` for exactly how
  much of it is read. Scalars come back as strings, numbers or booleans, and
  lists as lists.
  """
  @spec frontmatter(String.t()) :: Frontmatter.meta()
  defdelegate frontmatter(content), to: Frontmatter, as: :meta

  defp strip_order_prefix(name), do: Markdown.strip_order_prefix(name)

  # ---------------------------------------------------------------------------
  # Blog
  # ---------------------------------------------------------------------------

  @doc """
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
    * `:description`, `:image`, `:keywords`, `:tags` – frontmatter
    * `:authors` – resolved from `_authors/<key>.md` beside the posts:
      `%{key, name, title, url, image}`, with a key that has no file
      answering its key as its name
    * `:reading_minutes` – at two hundred words a minute, never under one
  """
  @spec list_blog_posts() :: [map()]
  def list_blog_posts do
    cached(:blog_posts, fn ->
      case path(:blog) do
        nil ->
          []

        dir ->
          authors = blog_authors(dir)

          dir
          |> Path.join("**/*.md")
          |> Path.wildcard()
          |> Enum.reject(&hidden_path?(&1, dir))
          |> Enum.map(&parse_blog_post(&1, authors))
          |> Enum.sort_by(& &1.date, {:desc, Date})
      end
    end)
  end

  # `_authors/dragos.md`, a `_drafts/` folder, a `_template.md`: an underscore
  # anywhere in the path below the blog root means "not a post".
  defp hidden_path?(path, dir) do
    path
    |> Path.relative_to(dir)
    |> Path.split()
    |> Enum.any?(&String.starts_with?(&1, "_"))
  end

  defp blog_authors(dir) do
    dir
    |> Path.join("_authors/*.md")
    |> Path.wildcard()
    |> Map.new(fn path ->
      key = Path.basename(path, ".md")
      meta = Frontmatter.meta(File.read!(path))

      {key,
       %{
         key: key,
         name: string(meta["name"]) || key,
         title: string(meta["title"]),
         url: string(meta["url"]),
         image: string(meta["image"])
       }}
    end)
  end

  @doc """
  Returns a single blog post map by slug, or `nil`.
  """
  @spec get_blog_post(String.t()) :: map() | nil
  def get_blog_post(slug) when is_binary(slug) do
    Enum.find(list_blog_posts(), fn p -> p.slug == slug end)
  end

  @doc """
  Returns `{prev_post, next_post}` neighbours for the given slug (newest-first order).
  Either may be `nil`.
  """
  @spec blog_neighbours(String.t()) :: {map() | nil, map() | nil}
  def blog_neighbours(slug) do
    posts = list_blog_posts()
    idx = Enum.find_index(posts, fn p -> p.slug == slug end)

    if idx do
      prev = if idx > 0, do: Enum.at(posts, idx - 1)
      next = Enum.at(posts, idx + 1)
      {prev, next}
    else
      {nil, nil}
    end
  end

  @doc """
  Renders a blog post's markdown to HTML, or `nil`.
  """
  @spec blog_post_html(String.t()) :: String.t() | nil
  def blog_post_html(slug) do
    cached({:blog_html, slug}, fn ->
      case get_blog_post(slug) do
        nil ->
          nil

        post ->
          entry = Map.get(registered_paths(), "blog", %{})

          post.path
          |> Markdown.render_file(
            collection: "blog",
            assets: Map.get(entry, :assets, :content),
            id: "post-" <> slug
          )
          |> case do
            nil -> nil
            html -> html |> Markdown.strip_first_h1() |> strip_lede(post)
          end
      end
    end)
  end

  # The show page renders the lede above the body when the post has no
  # description; then the body's first paragraph is that lede and is dropped
  # here, or every post opens by repeating itself.
  defp strip_lede(html, %{lede_in_body?: true, lede: lede}), do: strip_lede_paragraph(html, lede)
  defp strip_lede(html, _post), do: html

  @doc """
  Groups blog posts by `{year, month}` (newest first).
  Returns a list of `{year, [{month, [posts]}]}`.
  """
  @spec blog_posts_grouped() :: [{integer(), [{integer(), [map()]}]}]
  def blog_posts_grouped do
    list_blog_posts()
    |> Enum.group_by(fn p -> {p.date.year, p.date.month} end)
    |> Enum.sort_by(fn {{y, m}, _} -> {y, m} end, :desc)
    |> Enum.group_by(fn {{y, _m}, _posts} -> y end, fn {{_y, m}, posts} -> {m, posts} end)
    |> Enum.sort_by(fn {y, _} -> y end, :desc)
  end

  @truncate_marker ~r/<!--\s*truncate\s*-->/

  defp parse_blog_post(path, authors) do
    filename = Path.basename(path, ".md")
    {file_date, file_slug} = extract_date_and_slug(filename)
    {meta, body} = Frontmatter.parse(File.read!(path))

    description = string(meta["description"])
    lede = extract_lede(body)
    truncated = truncated_excerpt(body)

    excerpt =
      cond do
        description -> description
        truncated -> truncated
        true -> String.slice(lede, 0, 200)
      end

    %{
      slug: string(meta["slug"]) |> then(&(&1 && String.trim(&1, "/"))) || file_slug,
      title: string(meta["title"]) || extract_title(body) || humanize_slug(file_slug),
      date: meta_date(meta["date"]) || file_date,
      path: path,
      excerpt: excerpt,
      lede: lede,
      # A description or a truncate marker means the page shows *that* above
      # the body, so the first paragraph stays where it is.
      lede_in_body?: is_nil(description) and is_nil(truncated),
      description: description,
      image: string(meta["image"]),
      keywords: Frontmatter.list(meta["keywords"]),
      tags: Frontmatter.list(meta["tags"]),
      authors:
        meta["authors"]
        |> Frontmatter.list()
        |> Enum.map(&Map.get(authors, &1, %{key: &1, name: &1, title: nil, url: nil, image: nil})),
      reading_minutes: reading_minutes(body)
    }
  end

  defp truncated_excerpt(body) do
    case Regex.split(@truncate_marker, body, parts: 2) do
      [above, _below] -> above |> extract_lede() |> String.slice(0, 300)
      _ -> nil
    end
  end

  defp reading_minutes(body) do
    words = body |> String.split(~r/\s+/, trim: true) |> length()
    max(1, div(words + 199, 200))
  end

  defp meta_date(nil), do: nil

  defp meta_date(value) when is_binary(value) do
    value = String.trim(value)

    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp meta_date(_other), do: nil

  defp extract_date_and_slug(filename) do
    case Regex.run(~r/^(\d{4}-\d{2}-\d{2})-(.+)$/, filename) do
      [_, date_str, slug] ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> {date, slug}
          _ -> {file_date_fallback(), filename}
        end

      _ ->
        {file_date_fallback(), filename}
    end
  end

  defp file_date_fallback, do: Date.utc_today()

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp registered_paths do
    defaults = %{
      "changelog" => %{
        kind: :file,
        candidates: configured_candidates(:changelog_candidates),
        asset_root: :dirname
      },
      "roadmap" => %{
        kind: :file,
        candidates: configured_candidates(:roadmap_candidates)
      },
      "blog" => %{
        kind: :dir,
        candidates: configured_candidates(:blog_candidates),
        asset_root: :self
      }
    }

    Map.merge(defaults, registered_path_overrides())
  end

  defp registered_path_overrides, do: :persistent_term.get(@registered_paths_key, %{})

  defp normalize_registered_entry!(opts) do
    kind = Keyword.fetch!(opts, :kind)

    if kind not in [:file, :dir] do
      raise ArgumentError, "registered content path kind must be :file or :dir"
    end

    candidates =
      opts
      |> Keyword.get(:candidates, Keyword.get(opts, :path))
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))

    if candidates == [] do
      raise ArgumentError, "registered content path must include :path or :candidates"
    end

    asset_root =
      Keyword.get_lazy(opts, :asset_root, fn ->
        if kind == :file, do: :dirname, else: :self
      end)

    if asset_root not in [:self, :dirname] do
      raise ArgumentError, "registered content path asset_root must be :self or :dirname"
    end

    nesting = Keyword.get(opts, :nesting, :flat)

    if nesting not in [:flat, :tree] do
      raise ArgumentError, "registered content path nesting must be :flat or :tree"
    end

    assets = Keyword.get(opts, :assets, :content)

    if assets not in [:content, :static] do
      raise ArgumentError, "registered content path assets must be :content or :static"
    end

    %{
      kind: kind,
      candidates: candidates,
      asset_root: asset_root,
      post_render: normalize_post_render!(Keyword.get(opts, :post_render)),
      nesting: nesting,
      base_path: Keyword.get(opts, :base_path),
      assets: assets
    }
  end

  defp normalize_post_render!(nil), do: nil

  defp normalize_post_render!({module, function} = hook)
       when is_atom(module) and is_atom(function),
       do: hook

  defp normalize_post_render!(_other) do
    raise ArgumentError, "registered content path post_render must be {module, function}"
  end

  defp normalize_registered_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_registered_name(name) when is_binary(name), do: name

  defp configured_candidates(key) do
    (Application.get_env(:gamend_core, __MODULE__, []) || [])
    |> Keyword.get(key, Keyword.fetch!(@default_content_config, key))
  end

  defp serve_asset(nil, _relative), do: nil

  defp serve_asset(base_dir, relative) do
    base = Path.expand(base_dir)
    clean = Path.expand(relative, base)

    if inside_dir?(clean, base) and File.regular?(clean) do
      clean
    else
      nil
    end
  end

  defp inside_dir?(path, dir) do
    path
    |> Path.split()
    |> List.starts_with?(Path.split(dir))
  end

  defp find_existing_file(paths) when is_list(paths) do
    Enum.find_value(paths, fn path ->
      expanded = Path.expand(path, File.cwd!())

      if File.regular?(expanded), do: expanded, else: nil
    end)
  end

  defp find_existing_dir(paths) when is_list(paths) do
    Enum.find_value(paths, fn path ->
      expanded = Path.expand(path, File.cwd!())

      if File.dir?(expanded), do: expanded, else: nil
    end)
  end

  # The changelog and roadmap: one file, no tree, images beside it.
  defp render_markdown_file(path, content_type) do
    Markdown.render_file(path, collection: content_type, id: content_type)
  end

  defp extract_title(content) do
    content
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#\s+(.+)$/, String.trim(line)) do
        [_, title] -> String.trim(title)
        _ -> nil
      end
    end)
  end

  # A short summary for a card or a meta description, where the full paragraph
  # would not fit.
  defp extract_excerpt(content), do: content |> extract_lede() |> String.slice(0, 200)

  # The whole first paragraph, not its first line. Markdown is hard-wrapped, so
  # taking one line cut every excerpt off mid-sentence — "Measured numbers, not
  # estimates. Everything below comes from the k6 harness in" was what a card
  # and a `<meta name="description">` actually said.
  #
  # Given the *body*, after the frontmatter: a post with a `---` block used to
  # open with `title: …` as its lede.
  defp extract_lede(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.drop_while(&(&1 == "" or not prose_line?(&1)))
    |> Enum.take_while(&(&1 != ""))
    |> Enum.join(" ")
    |> String.trim()
    |> strip_markdown_inline()
  end

  # An import line, a video tag, a fence: none of these is the opening
  # sentence, and the paragraph after them is.
  defp prose_line?(line) do
    not String.starts_with?(line, ["#", "<", "```", ":::", "import ", "|", "![", "@@"])
  end

  # Strip common inline markdown syntax so excerpts read as plain text.
  defp strip_markdown_inline(text) do
    text
    # [text](url) → text
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/, "\\1")
    # ![alt](url) → alt
    |> String.replace(~r/!\[([^\]]*)\]\([^)]*\)/, "\\1")
    # **bold** or __bold__ → bold
    |> String.replace(~r/(\*\*|__)(.+?)\1/, "\\2")
    # *italic* or _italic_ → italic
    |> String.replace(~r/(\*|_)(.+?)\1/, "\\2")
    # `code` → code
    |> String.replace(~r/`([^`]+)`/, "\\1")
    # collapse multiple spaces
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp humanize_slug(slug) do
    slug
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # The show page renders the lede above the body, and the lede *is* the body's
  # first paragraph — so that paragraph is dropped here or every post opens by
  # repeating itself. Only an exact match is removed; an edited opening
  # paragraph stays.
  #
  # The first paragraph with any text, as `extract_lede/1` takes the first
  # prose line: a post that opens with an image renders it as a `<p>` of its
  # own, and checking only the first `<p>` left such a post repeating its lede.
  defp strip_lede_paragraph(html, lede) when is_binary(lede) and lede != "" do
    ~r/<p>(.*?)<\/p>\s*/s
    |> Regex.scan(html, return: :index)
    |> Enum.find(fn [_full, {start, length}] ->
      normalize_text(binary_part(html, start, length)) != ""
    end)
    |> case do
      [{start, length} = _full, {text_start, text_length}] ->
        if normalize_text(binary_part(html, text_start, text_length)) == normalize_text(lede) do
          binary_part(html, 0, start) <>
            binary_part(html, start + length, byte_size(html) - start - length)
        else
          html
        end

      nil ->
        html
    end
  end

  defp strip_lede_paragraph(html, _lede), do: html

  defp normalize_text(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp string(value) when is_binary(value) and value != "", do: value
  defp string(_other), do: nil

  # Pill tag definitions: [tag] → {css_class_suffix, display_label}
  @changelog_tags %{
    "fix" => {"fix", "Fix"},
    "fixed" => {"fix", "Fix"},
    "added" => {"added", "Added"},
    "add" => {"added", "Added"},
    "new" => {"added", "New"},
    "bug" => {"bug", "Bug"},
    "changed" => {"changed", "Changed"},
    "change" => {"changed", "Changed"},
    "removed" => {"removed", "Removed"},
    "remove" => {"removed", "Removed"},
    "security" => {"security", "Security"},
    "breaking" => {"breaking", "Breaking"},
    "deprecated" => {"deprecated", "Deprecated"},
    "perf" => {"perf", "Perf"},
    "docs" => {"docs", "Docs"},
    "started" => {"started", "Started"},
    "investigated" => {"investigated", "Investigated"},
    "idea" => {"idea", "Idea"},
    "plan" => {"plan", "Plan"},
    "planned" => {"plan", "Planned"}
  }

  @doc """
  Converts `[tag]` markers in changelog or roadmap HTML into coloured badges.

  A catch-all: any `[word]` becomes a pill, known tags in their own colour and
  everything else in the neutral one. That is deliberate for a changelog, where
  every line opens with a marker and an unrecognised one is a typo worth
  seeing — unlike the guide, where brackets are prose.

  Applied inside `changelog_html/0` and `roadmap_html/0`, so the result is
  cached. Labels here are **English literals and must stay that way**: a
  translated label baked into the cache would be served to every other locale.
  A host that wants translated pills re-labels them per request — see `pill/2`.
  """
  @spec apply_changelog_pills(String.t()) :: String.t()
  def apply_changelog_pills(html) do
    Regex.replace(
      ~r/\[([a-zA-Z]+)\]/,
      html,
      fn _full, tag ->
        key = String.downcase(tag)

        case Map.get(@changelog_tags, key) do
          {class_suffix, label} -> pill(class_suffix, label)
          nil -> pill("other", String.capitalize(tag))
        end
      end
    )
  end

  @doc """
  One pill badge: `class_suffix` picks the colour, `label` is what it reads.

  The markup lives here rather than at each call site because a host that adds
  its own tags — Polyglot Pirates re-labels the roadmap's in the reader's
  language — was copying this line, class name and all, and would not notice
  the day the stylesheet changed underneath it.
  """
  @spec pill(String.t(), String.t()) :: String.t()
  def pill(class_suffix, label),
    do: ~s(<span class="changelog-pill changelog-pill-#{class_suffix}">#{label}</span>)

  @doc """
  Re-labels pills that `apply_changelog_pills/1` rendered as neutral `other`.

  The one seam a translated pill can use. `apply_changelog_pills/1` runs inside
  the cache with English labels, so a host cannot translate there; this runs on
  the way out, per request, and takes `%{"tag" => {class_suffix, label}}` with
  the label already translated.

  Both spellings are handled: a marker that reached the cache is already a
  neutral `<span>`, while one written after the fact is still `[Tag]` — the
  roadmap has had both, and handling only the first left `[Beta]` printed
  verbatim in the middle of a heading.
  """
  @spec relabel_pills(String.t() | nil, %{optional(String.t()) => {String.t(), String.t()}}) ::
          String.t() | nil
  def relabel_pills(nil, _tags), do: nil

  def relabel_pills(html, tags) when is_map(tags) do
    Enum.reduce(tags, html, fn {tag, {class_suffix, label}}, acc ->
      acc
      |> String.replace(pill("other", tag), pill(class_suffix, label))
      |> String.replace("[#{tag}]", pill(class_suffix, label))
    end)
  end
end
