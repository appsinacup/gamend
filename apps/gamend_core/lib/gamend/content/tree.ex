defmodule Gamend.Content.Tree do
  @moduledoc """
  A guide collection read as a tree: folders are categories, at any depth.

  The one-level layout `Gamend.Content` started with — `10-setup/50-theme.md`,
  a folder per category and nothing deeper — is what a handful of guides
  want. A manual with a reference section of a hundred pages wants
  `reference/components/body2d.md`, a category inside a category, an
  `index.md` that *is* the category's page, and URLs that keep that shape.
  This module reads that layout; the flat one stays where it was.

  ## What the file tree says

  * A folder is a category. Its `_category.md` names it (`title`, `icon`,
    `color`, `position`, `collapsed`, `description`); without one, the folder
    name is humanised.
  * `index.md` in a folder is that category's own page, at the category's
    slug. Without one, the category still has a page — the renderer lists
    its children.
  * A file is a guide. Its slug is its path with each segment's order prefix
    stripped and the extension dropped: `10-manual/20-scenes.md` is
    `manual/scenes`. Frontmatter `slug` overrides that — `/reference` for the
    whole thing, or a bare name for the last segment.
  * Order is frontmatter `position` (or `sidebar_position`), then the numeric
    filename prefix, then the name. A guide with neither sorts after every
    guide with one.
  * A name beginning with `_` is not content: `_category.md`, `_authors/`,
    a `_features.md` partial another file includes.
  """

  alias Gamend.Content.Frontmatter
  alias Gamend.Content.Markdown

  require Gamend.Content.PageName, as: ContentPage

  @index ContentPage.index()

  @type doc :: %{
          type: :doc,
          slug: String.t(),
          path: Path.t(),
          dir: String.t(),
          title: String.t(),
          label: String.t(),
          summary: String.t(),
          description: String.t() | nil,
          image: String.t() | nil,
          keywords: [String.t()],
          icon: String.t(),
          color: String.t(),
          position: integer() | nil,
          category: String.t() | nil,
          index?: boolean(),
          meta: Frontmatter.meta()
        }

  @type category :: %{
          type: :category,
          slug: String.t(),
          dir: String.t(),
          title: String.t(),
          label: String.t(),
          icon: String.t(),
          color: String.t(),
          description: String.t() | nil,
          position: integer() | nil,
          collapsed: boolean(),
          category: String.t() | nil,
          index: doc() | nil,
          children: [entry()]
        }

  @type entry :: doc() | category()

  @type opts :: [
          doc_icon: String.t(),
          category_icon: String.t(),
          category_color: String.t()
        ]

  @unpositioned 1_000_000

  @doc "Read a collection root into an ordered tree."
  @spec scan(Path.t(), opts()) :: [entry()]
  def scan(root, opts \\ []) do
    scan_dir(root, "", nil, opts)
  end

  @doc "Every guide in reading order: a category's own page, then its children."
  @spec flatten([entry()]) :: [doc()]
  def flatten(tree) do
    Enum.flat_map(tree, fn
      %{type: :doc} = doc ->
        [doc]

      %{type: :category, index: index, children: children} ->
        List.wrap(index) ++ flatten(children)
    end)
  end

  @doc "Every category, depth first."
  @spec categories([entry()]) :: [category()]
  def categories(tree) do
    Enum.flat_map(tree, fn
      %{type: :doc} -> []
      %{type: :category, children: children} = category -> [category | categories(children)]
    end)
  end

  @doc "A guide by slug. A category's own page answers to the category's slug."
  @spec find_doc([entry()], String.t()) :: doc() | nil
  def find_doc(tree, slug), do: tree |> flatten() |> Enum.find(&(&1.slug == slug))

  @doc "A category by slug."
  @spec find_category([entry()], String.t()) :: category() | nil
  def find_category(tree, slug), do: tree |> categories() |> Enum.find(&(&1.slug == slug))

  @doc """
  The categories above a slug, outermost first, then the guide or category
  itself. Empty for a slug the tree does not hold.
  """
  @spec breadcrumbs([entry()], String.t()) :: [entry()]
  def breadcrumbs(tree, slug) do
    case find_doc(tree, slug) || find_category(tree, slug) do
      nil -> []
      node -> ancestors(tree, node.category, [node])
    end
  end

  # Climbs from the node's category upwards, prepending each, so the list is
  # outermost-first without a reverse.
  defp ancestors(_tree, nil, acc), do: acc

  defp ancestors(tree, slug, acc) do
    case find_category(tree, slug) do
      nil -> acc
      category -> ancestors(tree, category.category, [category | acc])
    end
  end

  @doc "`{previous, next}` in reading order, either possibly nil."
  @spec neighbours([entry()], String.t()) :: {doc() | nil, doc() | nil}
  def neighbours(tree, slug) do
    docs = flatten(tree)

    case Enum.find_index(docs, &(&1.slug == slug)) do
      nil -> {nil, nil}
      0 -> {nil, Enum.at(docs, 1)}
      index -> {Enum.at(docs, index - 1), Enum.at(docs, index + 1)}
    end
  end

  ## Scanning

  defp scan_dir(root, dir, parent_slug, opts) do
    full = Path.join(root, dir)

    full
    |> File.ls!()
    |> Enum.reject(&String.starts_with?(&1, ["_", "."]))
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      path = Path.join(full, name)
      relative = if dir == "", do: name, else: Path.join(dir, name)

      cond do
        File.dir?(path) ->
          [category(root, relative, parent_slug, opts)]

        Path.extname(name) in [".md", ".mdx"] and Path.rootname(name) != @index ->
          [doc(root, relative, parent_slug, opts)]

        true ->
          []
      end
    end)
    |> Enum.sort_by(&{&1.position || @unpositioned, sort_name(&1)})
  end

  defp sort_name(%{path: path}), do: Path.basename(path)
  defp sort_name(%{dir: dir}), do: Path.basename(dir)

  defp category(root, dir, parent_slug, opts) do
    name = Path.basename(dir)
    meta = category_meta(root, dir)
    slug = join_slug(parent_slug, Markdown.strip_order_prefix(name))

    # Its own colour or its parent's, and everything under it follows, so a
    # page's icon reads as part of the section it is in.
    color = string(meta["color"]) || Keyword.get(opts, :category_color, "text-primary")
    opts = Keyword.put(opts, :category_color, color)

    title =
      string(meta["title"]) || string(meta["label"]) ||
        humanize(Markdown.strip_order_prefix(name))

    index =
      [".md", ".mdx"]
      |> Enum.map(&Path.join([root, dir, @index <> &1]))
      |> Enum.find(&File.regular?/1)
      |> case do
        nil -> nil
        path -> doc(root, Path.relative_to(path, root), parent_slug, opts, slug)
      end

    %{
      type: :category,
      slug: slug,
      dir: dir,
      title: title,
      label: string(meta["label"]) || title,
      icon: string(meta["icon"]) || Keyword.get(opts, :category_icon, "hero-folder-solid"),
      color: color,
      description: string(meta["description"]) || (index && index.description),
      position: position(meta, name),
      collapsed: meta["collapsed"] != false,
      category: parent_slug,
      index: index,
      children: scan_dir(root, dir, slug, opts)
    }
  end

  defp category_meta(root, dir) do
    path = Path.join([root, dir, "_category.md"])
    if File.regular?(path), do: Frontmatter.meta(File.read!(path)), else: %{}
  end

  defp doc(root, relative, parent_slug, opts, forced_slug \\ nil) do
    content = File.read!(Path.join(root, relative))
    {meta, body} = Frontmatter.parse(content)
    name = Path.basename(relative) |> Path.rootname()
    dir = relative |> Path.dirname() |> then(&if(&1 == ".", do: "", else: &1))

    slug = forced_slug || slug(meta["slug"], parent_slug, Markdown.strip_order_prefix(name))
    title = string(meta["title"]) || heading(body) || humanize(Markdown.strip_order_prefix(name))
    description = string(meta["description"])

    %{
      type: :doc,
      slug: slug,
      path: Path.join(root, relative),
      dir: dir,
      title: title,
      label: string(meta["sidebar_label"]) || string(meta["label"]) || title,
      summary: description || excerpt(body),
      description: description,
      image: string(meta["image"]),
      keywords: Frontmatter.list(meta["keywords"]),
      icon: string(meta["icon"]) || Keyword.get(opts, :doc_icon, "hero-document-text-solid"),
      color: Keyword.get(opts, :category_color, "text-primary"),
      position: position(meta, Path.basename(relative)),
      category: parent_slug,
      index?: forced_slug != nil,
      meta: meta
    }
  end

  # `/reference` names the whole slug; `components` names the last segment.
  defp slug("/" <> absolute, _parent, _name), do: String.trim(absolute, "/")
  defp slug(nil, parent, name), do: join_slug(parent, name)
  defp slug("", parent, name), do: join_slug(parent, name)

  defp slug(bare, parent, _name) when is_binary(bare),
    do: join_slug(parent, String.trim(bare, "/"))

  defp slug(_other, parent, name), do: join_slug(parent, name)

  defp join_slug(nil, name), do: name
  defp join_slug("", name), do: name
  defp join_slug(parent, name), do: parent <> "/" <> name

  defp position(meta, filename) do
    Frontmatter.integer(meta["position"]) ||
      Frontmatter.integer(meta["sidebar_position"]) ||
      prefix_number(filename)
  end

  defp prefix_number(filename) do
    case Regex.run(~r/^(\d+)[-_]/, filename) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp heading(body) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#\s+(.+)$/, String.trim(line)) do
        [_, title] -> String.trim(title)
        _ -> nil
      end
    end)
  end

  # The first paragraph, cut for a card. Lines that are headings, imports,
  # fences, directives or raw tags are not prose and are skipped.
  defp excerpt(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.drop_while(&(&1 == "" or not prose?(&1)))
    |> Enum.take_while(&(&1 != ""))
    |> Enum.join(" ")
    |> strip_inline()
    |> String.slice(0, 200)
  end

  defp prose?(line) do
    not String.starts_with?(line, ["#", "<", "```", ":::", "import ", "|", "!["])
  end

  defp strip_inline(text) do
    text
    |> String.replace(~r/!\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/(\*\*|__)(.+?)\1/, "\\2")
    |> String.replace(~r/(\*|_)(.+?)\1/, "\\2")
    |> String.replace(~r/`([^`]+)`/, "\\1")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp humanize(name) do
    name
    |> String.replace(~r/[-_]/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp string(value) when is_binary(value) and value != "", do: value
  defp string(_other), do: nil
end
