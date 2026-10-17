defmodule GamendWeb.DocsLive do
  @moduledoc """
  The shared renderer for a markdown guide collection: an index and a page.

  A guide is a markdown file and nothing else — the folder gives its category,
  the numeric filename prefix its order, the first heading its title, and
  optional front matter its heroicon. A folder's `_category.md` names the
  category and gives it an icon and a colour, which its guides inherit so each
  section reads as one group. Adding one takes no Elixir change.

  ## Why this is in core

  Three copies of this page existed: gamend's public `/docs`, Polyglot
  Pirates' player guide at `/guide`, and its admin engineering docs at
  `/admin/docs` — the last two forked from the first, along with a second copy
  of the loader in `Gamend.Content`. They drifted in both directions. The
  guide grew pill badges, prev/next navigation, a coloured title icon and the
  standard Back button; the docs kept the sibling list, `:persistent_term`
  caching and a real 404. Every host wanted the union and no host had it.

  ## Why a `use` macro rather than a configured route

  A host needs its own `<title>` copy, its own gettext domain and its own base
  path, and `live/4` gives a LiveView nowhere to put any of that. A module per
  collection also keeps `GamendHost.PageMeta` and the router referring to a
  real module name, the way they already do.

      defmodule MyAppWeb.GuideLive do
        use GamendWeb.DocsLive,
          collection: :guide,
          index_path: "/guide",
          item_path: "/guide"

        def index_title, do: gettext("Player guide")
        def index_subtitle, do: gettext("How the game actually works.")
      end

  Options:

    * `:collection` — the `Gamend.Content` registered path name. Default `:docs`.
    * `:index_path` — where the index lives, for the "all guides" link.
    * `:item_path` — the prefix a guide's own URL is built from.
    * `:not_found` — `:raise` (a 404, the default) or `:redirect` back to the
      index. Only ever use `:redirect` off a public URL knowingly: a bad slug
      answering 200 is a soft 404, which is worse for a crawler than a hard one.
    * `:layout` — `:cards` (the default): an index of cards and a page with
      the sibling list, for a collection of a dozen guides. `:sidebar`: the
      whole tree in a column beside every page, a table of contents in
      another, breadcrumbs above, and a landing page for each category —
      for a manual with a reference section. The route for it is
      `live "/docs/*path"`, so a nested slug reaches `handle_params/3` whole.
    * `:edit_url` — a URL prefix the guide's path inside the collection is
      appended to, for an "Edit this page" link. `nil` shows none.

  ## Navigation carries both shapes

  Prev/next *and* the sibling list. A collection written to be read front to
  back needs the first; one read as reference needs the second; and a reader
  who wants neither loses nothing by their being there. Picking one per
  collection was the alternative, and it is a knob that exists only because
  two authors happened to write two pages.
  """

  use GamendWeb, :html

  alias Gamend.Content
  alias Gamend.Content.Tree

  @doc "The heading and `<title>` of the index page."
  @callback index_title() :: String.t()

  @doc "The line under the index heading, or `nil` for none."
  @callback index_subtitle() :: String.t() | nil

  @doc "Shown when the collection's directory is missing or empty."
  @callback empty_message() :: String.t()

  @doc false
  defmacro __using__(opts) do
    collection = Keyword.get(opts, :collection, :docs)
    index_path = Keyword.get(opts, :index_path, "/docs/setup")
    item_path = Keyword.get(opts, :item_path, "/docs")
    layout = Keyword.get(opts, :layout, :cards)
    edit_url = Keyword.get(opts, :edit_url)

    if layout not in [:cards, :sidebar] do
      raise ArgumentError,
            "GamendWeb.DocsLive :layout must be :cards or :sidebar, got: #{inspect(layout)}"
    end

    # Decided here rather than at runtime. A helper that took `:raise |
    # :redirect` and dispatched read fine and typed terribly: with `:raise`
    # always the argument, its only reachable clause never returns, so
    # dialyzer reported the call itself as one that "will not succeed" in
    # every host. Emitting one branch or the other makes the generated code
    # say what it does.
    not_found =
      case Keyword.get(opts, :not_found, :raise) do
        :raise ->
          quote(do: raise(GamendWeb.NotFoundError))

        :redirect ->
          quote(do: {:noreply, push_navigate(socket, to: unquote(index_path))})

        other ->
          raise ArgumentError,
                "GamendWeb.DocsLive :not_found must be :raise or :redirect, got: #{inspect(other)}"
      end

    # Which page renders which component is fixed by `:layout`, so the
    # dispatch is emitted for that layout alone. One `case` over both would
    # leave the other layout's clauses unreachable, which the compiler
    # reports — and a host compiles with warnings as errors.
    render_dispatch =
      case layout do
        :cards ->
          quote do
            case assigns.page do
              :show -> GamendWeb.DocsLive.show(assigns)
              _index -> GamendWeb.DocsLive.index(assigns)
            end
          end

        :sidebar ->
          quote do
            case assigns.page do
              :show -> GamendWeb.DocsLive.sidebar_show(assigns)
              :category -> GamendWeb.DocsLive.sidebar_category(assigns)
              _index -> GamendWeb.DocsLive.sidebar_index(assigns)
            end
          end
      end

    quote do
      use GamendWeb, :live_view

      @behaviour GamendWeb.DocsLive

      alias Gamend.Content
      alias GamendWeb.OnMount.SeoTitle

      @doc_collection unquote(collection)
      @doc_index_path unquote(index_path)
      @doc_item_path unquote(item_path)
      @doc_edit_url unquote(edit_url)

      @impl GamendWeb.DocsLive
      def index_title, do: gettext("Documentation")

      @impl GamendWeb.DocsLive
      def index_subtitle, do: nil

      @impl GamendWeb.DocsLive
      def empty_message, do: gettext("No guides found.")

      defoverridable GamendWeb.DocsLive

      @impl true
      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> assign(:categories, Content.list_doc_categories(@doc_collection))
         |> assign(:tree, Content.doc_tree(@doc_collection))
         |> assign(:page, :index)}
      end

      # The components are called as plain functions, not `<.show />`, so
      # their `attr` defaults never run — those are a call-site feature of the
      # HEEx compiler. Anything optional is therefore defaulted here instead.
      @impl true
      def render(assigns) do
        assigns =
          assigns
          |> GamendWeb.DocsLive.with_layout_assigns()
          |> assign(
            index_path: @doc_index_path,
            item_path: @doc_item_path,
            title: index_title(),
            subtitle: index_subtitle(),
            empty_message: empty_message()
          )

        unquote(render_dispatch)
      end

      # `live "/docs/*path"` hands the nested slug over as segments.
      @impl true
      def handle_params(%{"path" => segments}, uri, socket) when is_list(segments) do
        handle_params(%{"slug" => Enum.join(segments, "/")}, uri, socket)
      end

      def handle_params(%{"slug" => slug}, _uri, socket) do
        case {Content.get_doc(@doc_collection, slug),
              Content.get_doc_category(@doc_collection, slug)} do
          {nil, nil} ->
            unquote(not_found)

          {nil, category} ->
            {:noreply,
             socket
             |> SeoTitle.assign_page_title(category.title)
             |> assign(:page, :category)
             |> assign(:category_page, category)
             |> assign(:breadcrumbs, Content.doc_breadcrumbs(@doc_collection, slug))
             |> assign(:current_slug, slug)}

          {guide, _category} ->
            {prev, next} = Content.doc_neighbours(@doc_collection, slug)
            category = Content.doc_category(@doc_collection, slug)
            html = Content.doc_html(@doc_collection, slug)

            {:noreply,
             socket
             |> SeoTitle.assign_page_title(guide.title)
             |> assign(:page, :show)
             |> assign(:guide, guide)
             |> assign(:category, category)
             |> assign(:html, html)
             |> assign(:toc, Content.doc_toc(@doc_collection, slug))
             |> assign(:prev, prev)
             |> assign(:next, next)
             |> assign(:siblings, GamendWeb.DocsLive.siblings(category, slug))
             |> assign(:breadcrumbs, Content.doc_breadcrumbs(@doc_collection, slug))
             |> assign(:current_slug, slug)
             |> assign(
               :edit_url,
               GamendWeb.DocsLive.edit_url(@doc_edit_url, @doc_collection, guide)
             )}
        end
      end

      # `?guide=` is how the single-page version of these pages deep-linked a
      # section. Those links are in blog posts, chat history and the guides'
      # own cross-references, so they move to the guide's own URL rather than
      # silently landing on the index.
      def handle_params(%{"guide" => slug}, _uri, socket) do
        if Content.get_doc(@doc_collection, slug) do
          {:noreply, push_navigate(socket, to: "#{@doc_item_path}/#{slug}")}
        else
          {:noreply, socket |> assign(:page, :index) |> SeoTitle.assign_page_title(index_title())}
        end
      end

      def handle_params(_params, _uri, socket) do
        {:noreply,
         socket
         |> assign(:page, :index)
         |> assign(:current_slug, nil)
         |> SeoTitle.assign_page_title(index_title())}
      end

      defoverridable mount: 3, handle_params: 3, render: 1
    end
  end

  @doc """
  Fills in the assigns the layout reads but a LiveView does not always have.

  `current_path` is set by a plug that not every host mounts, and
  `current_scope` is absent on a public page with no session. Both are optional
  to the layout and neither can be defaulted by `attr` here — see `render/1`.
  """
  @spec with_layout_assigns(map()) :: map()
  def with_layout_assigns(assigns) do
    assigns
    |> assign_new(:current_path, fn -> nil end)
    |> assign_new(:current_scope, fn -> nil end)
    |> assign_new(:current_slug, fn -> nil end)
    |> assign_new(:breadcrumbs, fn -> [] end)
    |> assign_new(:toc, fn -> [] end)
    |> assign_new(:edit_url, fn -> nil end)
  end

  @doc """
  The other guides in a guide's category, in reading order.

  Empty rather than nil when the guide is alone in its category — or has no
  `_category.md` at all — so the template's `:if` reads as a list check.
  """
  @spec siblings(map() | nil, String.t()) :: [map()]
  def siblings(nil, _slug), do: []

  def siblings(category, slug), do: Enum.reject(category.guides, &(&1.slug == slug))

  @doc "The guide's file, under the collection's edit URL. `nil` without one."
  @spec edit_url(String.t() | nil, atom(), map()) :: String.t() | nil
  def edit_url(nil, _collection, _guide), do: nil

  def edit_url(base, collection, %{path: path}) do
    case Content.path(collection) do
      nil -> nil
      root -> String.trim_trailing(base, "/") <> "/" <> Path.relative_to(path, root)
    end
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :categories, :list, required: true
  attr :item_path, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :empty_message, :string, required: true

  @doc """
  The index: every category, every guide's title and summary.

  Titles and summaries only. Repeating the bodies here would make every guide
  duplicate content competing with itself, and make the index the longest page
  in the collection.
  """
  def index(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="space-y-6">
        <.header back_href={home_path()}>
          {@title}
          <:subtitle :if={@subtitle}>{@subtitle}</:subtitle>
        </.header>

        <p :if={@categories == []} class="text-muted">{@empty_message}</p>

        <section :for={category <- @categories} class="space-y-2">
          <h2 class="flex items-center gap-2 border-t border-base-300/60 pt-6 font-semibold uppercase tracking-[0.24em]">
            <.icon name={category.icon} class={"size-5 #{category.color}"} />
            {category.category}
          </h2>

          <.link
            :for={guide <- category.guides}
            navigate={"#{@item_path}/#{guide.slug}"}
            class="card block bg-base-100 shadow-sm transition-shadow hover:shadow-md"
          >
            <div class="card-body flex-row items-center gap-3 py-4">
              <.icon name={guide.icon} class={"size-6 shrink-0 opacity-80 #{category.color}"} />
              <%!-- The title wraps rather than push the card off a phone,
                    where the one-line summary has no room and is left out. --%>
              <span class="card-title min-w-0 text-xl">{guide.title}</span>
              <span class="hidden min-w-0 flex-1 basis-0 text-sm text-muted sm:line-clamp-1">
                {guide.summary}
              </span>
              <.icon name="hero-chevron-right" class="ms-auto size-4 shrink-0" />
            </div>
          </.link>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :guide, :map, required: true
  attr :category, :map, default: nil
  attr :html, :string, default: nil
  attr :prev, :map, default: nil
  attr :next, :map, default: nil
  attr :siblings, :list, default: []
  attr :index_path, :string, required: true
  attr :item_path, :string, required: true

  @doc """
  One guide: title, body, then both navigations.

  No category eyebrow above the title. The category is on the title icon as a
  colour and named again at the foot of the page, where "More in Operations"
  heads a list you can act on — an uppercase band between the breadcrumb and
  the heading said it a third time and linked nowhere.
  """
  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <article class="space-y-6">
        <%!-- `.header back=` is the same Back button as every other page with a
              parent, on the title's own line rather than a stray text link
              floating above it. --%>
        <.header back={@index_path} class="flex items-center gap-3">
          <.icon
            name={@guide.icon}
            class={"size-8 shrink-0 opacity-80 #{(@category && @category.color) || "text-primary"}"}
          />
          {@guide.title}
        </.header>

        <%!-- `markdown-content`, not `prose`: the Tailwind Typography plugin is
              not installed, so `prose` matches no rules at all and the body
              renders as unstyled text. `.markdown-content` is the hand-written
              stylesheet in `assets/css/app.css`. --%>
        <div class="markdown-content">{raw(@html)}</div>

        <.pager prev={@prev} next={@next} item_path={@item_path} />

        <nav :if={@siblings != []} class="space-y-2 border-t border-base-300/60 pt-6">
          <h2 class="text-sm font-semibold uppercase tracking-[0.24em]">
            {gettext("More in %{category}", category: (@category && @category.category) || "")}
          </h2>
          <ul class="space-y-1">
            <li :for={sibling <- @siblings}>
              <.link navigate={"#{@item_path}/#{sibling.slug}"} class="link link-hover">
                {sibling.title}
              </.link>
            </li>
          </ul>
        </nav>
      </article>
    </Layouts.app>
    """
  end

  ## The sidebar layout

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :tree, :list, required: true
  attr :item_path, :string, required: true
  attr :index_path, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :empty_message, :string, required: true
  attr :current_slug, :string, default: nil

  @doc "The collection's landing page, beside the tree: a card per top-level entry."
  def sidebar_index(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path} wide>
      <.sidebar_frame tree={@tree} item_path={@item_path} index_path={@index_path} title={@title}>
        <.header back_href={home_path()}>
          {@title}
          <:subtitle :if={@subtitle}>{@subtitle}</:subtitle>
        </.header>

        <p :if={@tree == []} class="text-muted">{@empty_message}</p>

        <.entry_cards entries={@tree} item_path={@item_path} />
      </.sidebar_frame>
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :tree, :list, required: true
  attr :item_path, :string, required: true
  attr :index_path, :string, required: true
  attr :title, :string, required: true
  attr :category_page, :map, required: true
  attr :breadcrumbs, :list, default: []
  attr :current_slug, :string, default: nil

  @doc """
  A category that has no `index.md` of its own: its title and description,
  then a card per child. A category *with* one renders as that guide, with
  these cards after its body.
  """
  def sidebar_category(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path} wide>
      <.sidebar_frame
        tree={@tree}
        item_path={@item_path}
        index_path={@index_path}
        title={@title}
        current_slug={@current_slug}
      >
        <.trail
          breadcrumbs={@breadcrumbs}
          item_path={@item_path}
          index_path={@index_path}
          title={@title}
        />

        <.header class="flex items-center gap-3">
          <.icon
            name={@category_page.icon}
            class={"size-8 shrink-0 opacity-80 #{@category_page.color}"}
          />
          {@category_page.title}
          <:subtitle :if={@category_page.description}>{@category_page.description}</:subtitle>
        </.header>

        <.entry_cards entries={@category_page.children} item_path={@item_path} />
      </.sidebar_frame>
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :tree, :list, required: true
  attr :item_path, :string, required: true
  attr :index_path, :string, required: true
  attr :title, :string, required: true
  attr :guide, :map, required: true
  attr :category, :map, default: nil
  attr :html, :string, default: nil
  attr :toc, :list, default: []
  attr :prev, :map, default: nil
  attr :next, :map, default: nil
  attr :breadcrumbs, :list, default: []
  attr :current_slug, :string, default: nil
  attr :edit_url, :string, default: nil

  @doc """
  One guide, three columns: the tree, the article, its table of contents.

  The table of contents is a column only from `xl`; below that it is a
  disclosure above the body, and the tree folds into one above that, so a
  phone reads the article first and the navigation on request.
  """
  def sidebar_show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path} wide>
      <.sidebar_frame
        tree={@tree}
        item_path={@item_path}
        index_path={@index_path}
        title={@title}
        current_slug={@current_slug}
        toc={@toc}
      >
        <.trail
          breadcrumbs={@breadcrumbs}
          item_path={@item_path}
          index_path={@index_path}
          title={@title}
        />

        <.header>
          {@guide.title}
          <:subtitle :if={@guide[:description]}>{@guide.description}</:subtitle>
        </.header>

        <details
          :if={@toc != []}
          class="collapse collapse-arrow border border-base-300/60 bg-base-100 xl:hidden"
        >
          <summary class="collapse-title min-h-0 py-3 text-sm font-semibold">
            {gettext("On this page")}
          </summary>
          <div class="collapse-content">
            <.toc_list toc={@toc} />
          </div>
        </details>

        <div class="markdown-content">{raw(@html)}</div>

        <.entry_cards
          :if={@guide[:index?] && category_page_children(@tree, @current_slug) != []}
          entries={category_page_children(@tree, @current_slug)}
          item_path={@item_path}
        />

        <div class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300/60 pt-4 text-sm">
          <a
            :if={@edit_url}
            href={@edit_url}
            class="link link-hover inline-flex items-center gap-1"
            rel="noopener"
            target="_blank"
          >
            <.icon name="hero-pencil-square" class="size-4" />
            {gettext("Edit this page")}
          </a>
          <span :if={!@edit_url}></span>
        </div>

        <.pager prev={@prev} next={@next} item_path={@item_path} />
      </.sidebar_frame>
    </Layouts.app>
    """
  end

  # The children of the category a guide is the index of, for the cards
  # after its body. Called from the template with the tree in hand, so it
  # is a function on assigns rather than another assign per page.
  @doc false
  def category_page_children(tree, slug) do
    case Tree.find_category(tree, slug) do
      nil -> []
      category -> category.children
    end
  end

  attr :tree, :list, required: true
  attr :item_path, :string, required: true
  attr :index_path, :string, required: true
  attr :title, :string, required: true
  attr :current_slug, :string, default: nil
  attr :toc, :list, default: []
  slot :inner_block, required: true

  # The grid the three sidebar pages share. Two columns from `lg`, a third
  # for the table of contents from `xl`; the tree is sticky and scrolls on
  # its own, so a long manual does not push the article's top off screen.
  defp sidebar_frame(assigns) do
    ~H"""
    <div class="grid gap-8 lg:grid-cols-[15rem_minmax(0,1fr)] xl:grid-cols-[15rem_minmax(0,1fr)_13rem]">
      <details class="collapse collapse-arrow border border-base-300/60 bg-base-100 lg:hidden">
        <summary class="collapse-title min-h-0 py-3 text-sm font-semibold">{@title}</summary>
        <div class="collapse-content">
          <.sidebar
            tree={@tree}
            item_path={@item_path}
            index_path={@index_path}
            title={@title}
            current_slug={@current_slug}
          />
        </div>
      </details>

      <aside class="hidden lg:block">
        <div class="sticky top-24 max-h-[calc(100dvh-7rem)] overflow-y-auto pe-2">
          <.sidebar
            tree={@tree}
            item_path={@item_path}
            index_path={@index_path}
            title={@title}
            current_slug={@current_slug}
          />
        </div>
      </aside>

      <article class="min-w-0 space-y-6">
        {render_slot(@inner_block)}
      </article>

      <aside :if={@toc != []} class="hidden xl:block">
        <nav class="sticky top-24 space-y-2 text-sm" aria-label={gettext("On this page")}>
          <p class="font-semibold uppercase tracking-[0.2em] text-muted">
            {gettext("On this page")}
          </p>
          <.toc_list toc={@toc} />
        </nav>
      </aside>
    </div>
    """
  end

  attr :tree, :list, required: true
  attr :item_path, :string, required: true
  attr :index_path, :string, required: true
  attr :title, :string, required: true
  attr :current_slug, :string, default: nil

  @doc """
  The tree as nested lists. A category is a `<details>` — open when the
  reader is inside it or the category asked to be — whose summary is the
  category's own page. `aria-current` marks the page being read.
  """
  def sidebar(assigns) do
    ~H"""
    <nav class="text-sm" aria-label={@title}>
      <.link
        navigate={@index_path}
        class={[
          "mb-2 block rounded-field px-2 py-1 font-semibold",
          if(is_nil(@current_slug), do: "bg-primary/10 text-primary", else: "hover:bg-base-200")
        ]}
        aria-current={is_nil(@current_slug) && "page"}
      >
        {@title}
      </.link>
      <.sidebar_entries entries={@tree} item_path={@item_path} current_slug={@current_slug} depth={0} />
    </nav>
    """
  end

  attr :entries, :list, required: true
  attr :item_path, :string, required: true
  attr :current_slug, :string, default: nil
  attr :depth, :integer, default: 0

  defp sidebar_entries(assigns) do
    ~H"""
    <ul class={["space-y-0.5", @depth > 0 && "ms-3 border-s border-base-300/60 ps-2"]}>
      <li :for={entry <- @entries}>
        <%= if entry.type == :category do %>
          <details open={open?(entry, @current_slug)}>
            <summary class="flex cursor-pointer items-center gap-1 rounded-field px-2 py-1 font-medium hover:bg-base-200">
              <.icon
                name="hero-chevron-right"
                class="size-3 shrink-0 transition-transform [details[open]>summary>&]:rotate-90"
              />
              <.link
                navigate={"#{@item_path}/#{entry.slug}"}
                class={["grow", entry.slug == @current_slug && "text-primary"]}
                aria-current={entry.slug == @current_slug && "page"}
              >
                {entry.label}
              </.link>
            </summary>
            <.sidebar_entries
              entries={entry.children}
              item_path={@item_path}
              current_slug={@current_slug}
              depth={@depth + 1}
            />
          </details>
        <% else %>
          <.link
            navigate={"#{@item_path}/#{entry.slug}"}
            class={[
              "block rounded-field px-2 py-1",
              if(entry.slug == @current_slug,
                do: "bg-primary/10 font-medium text-primary",
                else: "hover:bg-base-200"
              )
            ]}
            aria-current={entry.slug == @current_slug && "page"}
          >
            {entry.label}
          </.link>
        <% end %>
      </li>
    </ul>
    """
  end

  # Open when the reader is on or under the category, or when its
  # `_category.md` said `collapsed: false`.
  defp open?(%{slug: slug, collapsed: collapsed}, current) do
    not collapsed or
      (is_binary(current) and (current == slug or String.starts_with?(current, slug <> "/")))
  end

  attr :toc, :list, required: true

  defp toc_list(assigns) do
    ~H"""
    <ul class="space-y-1">
      <li :for={heading <- @toc} class={heading.level == 3 && "ms-3"}>
        <a href={"##{heading.id}"} class="link link-hover text-muted">{heading.text}</a>
      </li>
    </ul>
    """
  end

  attr :breadcrumbs, :list, required: true
  attr :item_path, :string, required: true
  attr :index_path, :string, required: true
  attr :title, :string, required: true

  # The collection, then each category, then the page itself unlinked.
  defp trail(assigns) do
    ~H"""
    <nav
      :if={@breadcrumbs != []}
      aria-label={gettext("Breadcrumb")}
      class="text-sm text-muted"
    >
      <ol class="flex flex-wrap items-center gap-1">
        <li>
          <.link navigate={@index_path} class="link link-hover">{@title}</.link>
        </li>
        <li :for={{crumb, last?} <- with_last(@breadcrumbs)} class="flex items-center gap-1">
          <.icon name="hero-chevron-right" class="size-3" />
          <.link :if={!last?} navigate={"#{@item_path}/#{crumb.slug}"} class="link link-hover">
            {crumb.label}
          </.link>
          <span :if={last?} aria-current="page">{crumb.label}</span>
        </li>
      </ol>
    </nav>
    """
  end

  defp with_last(list) do
    count = length(list)
    Enum.with_index(list, fn item, index -> {item, index == count - 1} end)
  end

  attr :entries, :list, required: true
  attr :item_path, :string, required: true

  # A card per entry: a guide with its summary, a category with its
  # description and how many pages it holds.
  defp entry_cards(assigns) do
    ~H"""
    <div :if={@entries != []} class="grid gap-3 sm:grid-cols-2">
      <.link
        :for={entry <- @entries}
        navigate={"#{@item_path}/#{entry.slug}"}
        class="card bg-base-100 shadow-sm transition-shadow hover:shadow-md"
      >
        <div class="card-body gap-2 py-4">
          <span class="card-title flex items-center gap-2 text-base">
            <.icon
              name={entry.icon}
              class={"size-5 shrink-0 opacity-80 #{Map.get(entry, :color, "text-primary")}"}
            />
            {entry.label}
          </span>
          <span class="line-clamp-2 text-sm text-muted">
            {entry_summary(entry)}
          </span>
        </div>
      </.link>
    </div>
    """
  end

  defp entry_summary(%{type: :category} = category) do
    category.description ||
      ngettext("%{count} page", "%{count} pages", length(Tree.flatten([category])))
  end

  defp entry_summary(%{summary: summary}), do: summary

  attr :prev, :map, default: nil
  attr :next, :map, default: nil
  attr :item_path, :string, required: true

  defp pager(assigns) do
    ~H"""
    <nav
      :if={@prev || @next}
      class="flex justify-between gap-3 border-t border-base-300/60 pt-6"
      aria-label={gettext("More pages")}
    >
      <%!-- The empty span keeps `justify-between` pushing a lone "next"
            to the right on the first page. --%>
      <.link :if={@prev} navigate={"#{@item_path}/#{@prev.slug}"} class="btn btn-surface btn-sm">
        <.icon name="hero-chevron-left" class="size-4" />
        {@prev.title}
      </.link>
      <span :if={!@prev}></span>
      <.link :if={@next} navigate={"#{@item_path}/#{@next.slug}"} class="btn btn-surface btn-sm">
        {@next.title}
        <.icon name="hero-chevron-right" class="size-4" />
      </.link>
    </nav>
    """
  end
end
