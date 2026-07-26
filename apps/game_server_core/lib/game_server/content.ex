defmodule GameServer.Content do
  @moduledoc """
  Reads and renders Markdown content from project files and directories.

  Lookup is path-based rather than theme-config driven. Hosts register named
  content sources, and this module resolves whichever configured files or
  directories exist for those sources.

  All content is cached in `:persistent_term` after the first read.
  Call `reload/0` to invalidate everything (e.g. after a config change).
  """

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
  # Blog
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Docs
  # ---------------------------------------------------------------------------

  @doc """
  Lists every guide, grouped into categories in reading order.

  Structure comes from the file tree rather than front matter, so a guide is a
  file and nothing else has to be edited to add one:

      priv/docs/10-core-setup/20-deployment.md

  The numeric prefixes order categories and guides and are stripped from the
  slug; the folder name is the category; the title is the first `# ` heading.
  Returns `[%{category: String.t(), guides: [guide]}]`, each guide a map of
  `:slug`, `:title`, `:summary` and `:path`.
  """
  @spec list_doc_categories() :: [%{category: String.t(), guides: [map()]}]
  def list_doc_categories do
    cached(:doc_categories, fn ->
      case path(:docs) do
        nil ->
          []

        dir ->
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
    end)
  end

  @doc "Every guide as a flat list, in the same order as `list_doc_categories/0`."
  @spec list_docs() :: [map()]
  def list_docs do
    Enum.flat_map(list_doc_categories(), & &1.guides)
  end

  @doc "Returns a single guide map by slug, or `nil`."
  @spec get_doc(String.t()) :: map() | nil
  def get_doc(slug) when is_binary(slug) do
    Enum.find(list_docs(), fn doc -> doc.slug == slug end)
  end

  @doc """
  Renders a guide's markdown to HTML, or `nil`.

  The leading `# ` heading is dropped: the page renders the title itself, in
  the disclosure summary you click to open the guide.
  """
  @spec doc_html(String.t()) :: String.t() | nil
  def doc_html(slug) do
    cached({:doc_html, slug}, fn ->
      case get_doc(slug) do
        nil ->
          nil

        doc ->
          case render_markdown_file(doc.path, "docs") do
            nil -> nil
            html -> strip_first_h1(html)
          end
      end
    end)
  end

  defp parse_doc(path, root) do
    content = File.read!(path)
    meta = frontmatter(content)
    slug = path |> Path.basename(".md") |> strip_order_prefix()
    body = strip_frontmatter(content)

    %{
      slug: slug,
      title: extract_title(body) || humanize_slug(slug),
      summary: extract_excerpt(body),
      icon: Map.get(meta, "icon", @default_doc_icon),
      category: category_dir(path, root),
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

    meta = if File.exists?(path), do: frontmatter(File.read!(path)), else: %{}

    %{
      category: Map.get(meta, "title") || dir |> strip_order_prefix() |> humanize_slug(),
      icon: Map.get(meta, "icon", @default_category_icon),
      color: Map.get(meta, "color", @default_category_color)
    }
  end

  @doc """
  Reads a leading `---` fenced block of `key: value` lines.

  Deliberately not YAML: the values here are single-line strings, and a parser
  dependency for that would be its own liability.
  """
  @spec frontmatter(String.t()) :: %{String.t() => String.t()}
  def frontmatter("---\n" <> rest) do
    case String.split(rest, ~r/^---\s*$/m, parts: 2) do
      [block, _body] ->
        block
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ":", parts: 2) do
            [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
            _ -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  def frontmatter(_content), do: %{}

  defp strip_frontmatter("---\n" <> rest = content) do
    case String.split(rest, ~r/^---\s*$/m, parts: 2) do
      [_block, body] -> String.trim_leading(body)
      _ -> content
    end
  end

  defp strip_frontmatter(content), do: content

  # The highlighter ships no GDScript grammar, so a ```gdscript block renders
  # as flat text. JavaScript's grammar colours its keywords, strings and calls
  # closely enough; the markdown keeps saying gdscript, which is what a reader
  # should see.
  @language_aliases %{
    "gdscript" => "javascript",
    "gd" => "javascript",
    "godot" => "javascript"
  }

  defp alias_code_languages(content) do
    Regex.replace(~r/^```(\w+)[ \t]*$/m, content, fn full, lang ->
      case Map.fetch(@language_aliases, String.downcase(lang)) do
        {:ok, replacement} -> "```" <> replacement
        :error -> full
      end
    end)
  end

  # "20-deployment" -> "deployment". Ordering lives in the filename so the
  # tree reads in the same order it renders.
  defp strip_order_prefix(name), do: Regex.replace(~r/^\d+[-_]/, name, "")

  @doc """
  Lists all blog posts sorted newest-first.

  Each post is a map with keys:
    * `:slug`  – URL-safe identifier derived from the filename
    * `:title` – extracted from the first `# ` heading (or humanised slug)
    * `:date`  – `Date.t()` parsed from filename prefix or file mtime
    * `:path`  – absolute path to the `.md` file
    * `:excerpt` – first non-heading paragraph (≤ 200 chars)
  """
  @spec list_blog_posts() :: [map()]
  def list_blog_posts do
    cached(:blog_posts, fn ->
      case path(:blog) do
        nil ->
          []

        dir ->
          dir
          |> Path.join("**/*.md")
          |> Path.wildcard()
          |> Enum.map(&parse_blog_post/1)
          |> Enum.sort_by(& &1.date, {:desc, Date})
      end
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
          case render_markdown_file(post.path, "blog") do
            nil -> nil
            html -> html |> strip_first_h1() |> strip_lede_paragraph(post.excerpt)
          end
      end
    end)
  end

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

  # ---------------------------------------------------------------------------
  # Content asset serving
  # ---------------------------------------------------------------------------

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

    %{
      kind: kind,
      candidates: candidates,
      asset_root: asset_root
    }
  end

  defp normalize_registered_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_registered_name(name) when is_binary(name), do: name

  defp configured_candidates(key) do
    (Application.get_env(:game_server_core, __MODULE__, []) || [])
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

  defp render_markdown_file(path, content_type) do
    case File.read(path) do
      {:ok, content} ->
        content =
          content
          |> strip_frontmatter()
          |> alias_code_languages()
          |> fix_table_separators()

        case MDEx.to_html(content, markdown_options()) do
          {:ok, html} -> rewrite_relative_images(html, content_type)
          {:error, _reason} -> nil
        end

      _ ->
        nil
    end
  end

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

  defp markdown_options do
    [
      extension: [
        autolink: true,
        strikethrough: true,
        table: true,
        tasklist: true
      ],
      parse: [smart: false],
      # Linked rather than inline: the formatter emits token classes and the
      # colours live in app.css, so the same markup reads correctly in both
      # the light and dark themes. Inline styles would pin one palette.
      syntax_highlight: [engine: :lumis, opts: [formatter: :html_linked]],
      # The default sanitizer already preserves the highlighter's classes and
      # the language hint; narrowing it strips exactly that markup.
      sanitize: MDEx.Document.default_sanitize_options()
    ]
  end

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

  # Rewrite image `src` attributes so they point to `/content/<type>/…`,
  # which is served by the host content asset route.
  #
  # Handles three conventions authors may use:
  #   1. Relative:     `gamend/auth.png`        → `/content/blog/gamend/auth.png`
  #   2. Absolute:     `/gamend/auth.png`        → `/content/blog/gamend/auth.png`
  #   3. Type-prefixed: `/blog/gamend/auth.png`  → `/content/blog/gamend/auth.png`
  #
  # Also handles `<image>` tags (non-standard HTML) by converting them to `<img>`.
  # External URLs (`http…`) and already-rewritten `/content/…` paths are left alone.
  defp rewrite_relative_images(html, content_type) do
    # First, normalise <image … /> to <img … /> (browsers treat <image> as
    # synonymous with <img>, but it's non-standard and inconsistent).
    html = Regex.replace(~r/<image\b/, html, "<img")

    Regex.replace(
      ~r/<img([^>]*)\ssrc="([^"]+)"([^>]*)>/,
      html,
      fn full, before, src, after_attr ->
        cond do
          String.starts_with?(src, "http") ->
            full

          String.starts_with?(src, "/content/") ->
            add_lazy_image_attrs(full)

          true ->
            clean =
              src
              |> String.trim_leading("/")
              |> String.trim_leading("./")
              # Strip redundant type prefix (e.g. "blog/" from "/blog/gamend/img.png")
              |> strip_content_type_prefix(content_type)

            ~s(<img#{before} src="/content/#{content_type}/#{clean}"#{after_attr}>)
            |> add_lazy_image_attrs()
        end
      end
    )
  end

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

  defp parse_blog_post(path) do
    filename = Path.basename(path, ".md")
    {date, slug} = extract_date_and_slug(filename)
    content = File.read!(path)
    title = extract_title(content) || humanize_slug(slug)
    excerpt = extract_excerpt(content)

    %{
      slug: slug,
      title: title,
      date: date,
      path: path,
      excerpt: excerpt
    }
  end

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

  defp extract_excerpt(content) do
    content
    |> String.split("\n")
    |> Enum.reject(fn line ->
      trimmed = String.trim(line)
      trimmed == "" or String.starts_with?(trimmed, "#")
    end)
    |> List.first("")
    |> String.trim()
    |> strip_markdown_inline()
    |> String.slice(0, 200)
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

  # Remove the first <h1>...</h1> from rendered HTML since the blog post
  # header already displays the title separately.
  defp strip_first_h1(html) do
    Regex.replace(~r/<h1>.*?<\/h1>\s*/s, html, "", global: false)
  end

  # The show page renders the excerpt as a lede above the body, and the excerpt
  # *is* the body's first paragraph — so that paragraph is dropped here or every
  # post opens by repeating itself. Only an exact match is removed; an edited
  # opening paragraph stays.
  defp strip_lede_paragraph(html, excerpt) when is_binary(excerpt) and excerpt != "" do
    case Regex.run(~r/\A\s*<p>(.*?)<\/p>\s*/s, html) do
      [full, text] ->
        if normalize_text(text) == normalize_text(excerpt) do
          String.replace(html, full, "", global: false)
        else
          html
        end

      _ ->
        html
    end
  end

  defp strip_lede_paragraph(html, _excerpt), do: html

  defp normalize_text(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

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

  # Convert `[tag]` markers in changelog HTML into colored pill badges.
  # Matches patterns like `[fix]`, `[added]`, etc. at the start of list items.
  defp apply_changelog_pills(html) do
    Regex.replace(
      ~r/\[([a-zA-Z]+)\]/,
      html,
      fn _full, tag ->
        key = String.downcase(tag)

        case Map.get(@changelog_tags, key) do
          {class_suffix, label} ->
            ~s(<span class="changelog-pill changelog-pill-#{class_suffix}">#{label}</span>)

          nil ->
            label = String.capitalize(tag)
            ~s(<span class="changelog-pill changelog-pill-other">#{label}</span>)
        end
      end
    )
  end
end
