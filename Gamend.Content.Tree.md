# `Gamend.Content.Tree`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/content/tree.ex#L1)

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

# `category`

```elixir
@type category() :: %{
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
```

# `doc`

```elixir
@type doc() :: %{
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
  position: integer() | nil,
  category: String.t() | nil,
  index?: boolean(),
  meta: Gamend.Content.Frontmatter.meta()
}
```

# `entry`

```elixir
@type entry() :: doc() | category()
```

# `opts`

```elixir
@type opts() :: [
  doc_icon: String.t(),
  category_icon: String.t(),
  category_color: String.t()
]
```

# `breadcrumbs`

```elixir
@spec breadcrumbs([entry()], String.t()) :: [entry()]
```

The categories above a slug, outermost first, then the guide or category
itself. Empty for a slug the tree does not hold.

# `categories`

```elixir
@spec categories([entry()]) :: [category()]
```

Every category, depth first.

# `find_category`

```elixir
@spec find_category([entry()], String.t()) :: category() | nil
```

A category by slug.

# `find_doc`

```elixir
@spec find_doc([entry()], String.t()) :: doc() | nil
```

A guide by slug. A category's own page answers to the category's slug.

# `flatten`

```elixir
@spec flatten([entry()]) :: [doc()]
```

Every guide in reading order: a category's own page, then its children.

# `neighbours`

```elixir
@spec neighbours([entry()], String.t()) :: {doc() | nil, doc() | nil}
```

`{previous, next}` in reading order, either possibly nil.

# `scan`

```elixir
@spec scan(Path.t(), opts()) :: [entry()]
```

Read a collection root into an ordered tree.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
