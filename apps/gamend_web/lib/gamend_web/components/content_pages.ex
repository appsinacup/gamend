defmodule GamendWeb.ContentPages do
  @moduledoc """
  The changelog, roadmap and blog pages: one markup, two rendering styles.

  ## Why components rather than one LiveView

  gamend serves these as LiveViews; Polyglot Pirates serves them from a plain
  controller, because a changelog has nothing live on it and a dead render is
  one less socket. Both are defensible, and neither host should have to change
  to share the page — so what is shared is the *markup*, which a LiveView's
  `render/1` and a `.html.heex` template can both call.

  The three copies that existed before this said the same thing in three
  slightly different ways, and the differences were all accidents: gamend's
  `page_title` was an untranslated string and its empty-state body was an
  English literal, while Polyglot's had a card around the article and a
  reusable empty state. Nothing chose any of that; one was written after the
  other.

  The blog arrived here later for exactly that reason. It stayed a shim that
  looked up `GamendWeb.HostBlogLive` by name, so each host wrote the page
  itself: gamend and the starter carried byte-identical 237-line copies, each
  with its own private `group_blog_posts/1` reimplementing
  `Gamend.Content.blog_posts_grouped/0` — which was therefore dead in core. The
  copies had already drifted: the starter rendered dates with
  `Calendar.strftime`, so they never picked up the reader's timezone the way
  `<.timestamp>` does.

  The blog is shared the same way: `GamendWeb.BlogLive` renders it for any
  host that routes it, and Polyglot Pirates renders the same two components
  from its controller. The index is a grid, one layout for every host; it was
  a list with an opt-in grid for a day, and two layouts is one more than a
  page of cards needs.

  ## `href`, not `navigate`

  The cross-links between the changelog and roadmap are plain anchors. These
  are static documents where a full navigation is what happens anyway. The
  blog's links are `navigate`, which from `GamendWeb.BlogLive` keeps the
  socket and on a controller-rendered page is a plain link: LiveView's client
  leaves a live link to the browser when no LiveView is mounted.
  """

  use GamendWeb, :html

  alias Gamend.Content
  alias Gamend.Content.Markdown

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :html, :string, default: nil
  attr :roadmap_available?, :boolean, default: false

  @doc "The changelog page, with a link across to the roadmap when there is one."
  def changelog(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.content_page
        title={gettext("Changelog")}
        html={@html}
        sibling_path={@roadmap_available? && ~p"/roadmap"}
        sibling_icon="hero-map"
        sibling_label={gettext("Roadmap")}
        empty_icon="hero-document-text"
        empty_text={gettext("Add a changelog file at CHANGELOG.md to display it here.")}
      />
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :html, :string, default: nil
  attr :changelog_available?, :boolean, default: false

  @doc "The roadmap page, with a link across to the changelog when there is one."
  def roadmap(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.content_page
        title={gettext("Roadmap")}
        html={@html}
        sibling_path={@changelog_available? && ~p"/changelog"}
        sibling_icon="hero-document-text"
        sibling_label={gettext("Changelog")}
        empty_icon="hero-map"
        empty_text={gettext("Add a roadmap file at ROADMAP.md to display it here.")}
      />
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :html, :string, default: nil
  attr :sibling_path, :any, default: nil
  attr :sibling_icon, :string, required: true
  attr :sibling_label, :string, required: true
  attr :empty_icon, :string, required: true
  attr :empty_text, :string, required: true

  # The two pages differ only in their copy and which way the cross-link
  # points, so the shape is written once. `sibling_path` is false rather than
  # nil when the other page has no file, which `:if` reads the same way.
  defp content_page(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-row items-center justify-between gap-3">
        <div class="flex min-w-0 items-center gap-3">
          <.back_link href={home_path()} />
          <h1 class="text-4xl font-black text-base-content">{@title}</h1>
        </div>

        <.link :if={@sibling_path} href={@sibling_path} class="btn btn-surface btn-sm">
          <.icon name={@sibling_icon} class="size-4" />
          {@sibling_label}
        </.link>
      </div>

      <section
        :if={@html}
        class="rounded-3xl border border-base-300 bg-base-100/90 p-5 shadow-sm sm:p-8"
      >
        <article class="markdown-content">{raw(@html)}</article>
      </section>

      <.empty_state :if={!@html} icon={@empty_icon} title={gettext("No results.")} text={@empty_text} />
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :blog_available?, :boolean, default: false
  attr :grouped_posts, :list, default: []
  attr :changelog_available?, :boolean, default: false
  attr :roadmap_available?, :boolean, default: false

  @doc """
  The blog index: every post grouped by year and month, newest first, as a
  grid of cards — one to a row on a phone, two on a tablet, three on a
  desktop — each with its picture above its date, reading time, title,
  excerpt and authors.

  Takes `grouped_posts` in the shape `Gamend.Content.blog_posts_grouped/0`
  returns. A card's picture is the post's `:card_image`, else its `:image`.
  """
  def blog_index(assigns) do
    assigns = assign(assigns, :first_slug, first_slug(assigns.grouped_posts))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="py-8">
        <.empty_state
          :if={!@blog_available?}
          icon="hero-newspaper"
          title={gettext("No results.")}
          text={gettext("Register a blog directory to display posts here.")}
        />

        <div :if={@blog_available?}>
          <%!-- Wraps rather than squeezes: on a phone, "Feuille de route"
                and "Journal des modifications" do not fit beside the title. --%>
          <div class="mb-8 flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
            <div class="flex min-w-0 items-center gap-3">
              <.back_link href={home_path()} />
              <h1 class="text-3xl font-bold">{gettext("Blog")}</h1>
            </div>

            <div class="flex flex-wrap items-center gap-x-3 gap-y-1 whitespace-nowrap">
              <.link
                :if={@roadmap_available?}
                href={~p"/roadmap"}
                class="inline-flex items-center gap-1.5 text-sm text-muted transition-colors hover:text-primary"
              >
                <.icon name="hero-map" class="size-4" /> {gettext("Roadmap")}
              </.link>
              <.link
                :if={@changelog_available?}
                href={~p"/changelog"}
                class="inline-flex items-center gap-1.5 text-sm text-muted transition-colors hover:text-primary"
              >
                <.icon name="hero-document-text" class="size-4" /> {gettext("Changelog")}
              </.link>
            </div>
          </div>

          <.empty_state
            :if={@grouped_posts == []}
            icon="hero-pencil-square"
            title={gettext("No results.")}
          />

          <div :if={@grouped_posts != []} class="space-y-10">
            <section :for={{year, months} <- @grouped_posts}>
              <h2 class="mb-6 border-b border-base-300 pb-2 text-2xl font-bold text-base-content">
                {year}
              </h2>

              <div :for={{month, posts} <- months} class="mb-8">
                <h3 class="mb-4 text-sm font-semibold uppercase tracking-[0.22em] text-muted">
                  <.month_heading year={year} month={month} />
                </h3>

                <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
                  <article
                    :for={post <- posts}
                    class="overflow-hidden rounded-3xl border border-base-300 bg-base-100/95 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
                  >
                    <.link navigate={~p"/blog/#{post.slug}"} class="flex h-full flex-col">
                      <%!-- The post's picture, cropped to a landscape tile
                            above the text; whole on the post itself. The
                            newest post's is the first thing a reader sees,
                            so it is fetched first rather than lazily. --%>
                      <img
                        :if={card_image(post)}
                        src={card_image(post)}
                        alt=""
                        loading={if post.slug == @first_slug, do: "eager", else: "lazy"}
                        fetchpriority={if post.slug == @first_slug, do: "high"}
                        decoding="async"
                        class="aspect-video w-full object-cover"
                      />
                      <div class="space-y-2 p-5">
                        <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs uppercase tracking-[0.18em] text-muted">
                          <span><.timestamp at={post.date} format="date" /></span>
                          <span :if={post[:reading_minutes]}>
                            {reading_time(post.reading_minutes)}
                          </span>
                        </div>

                        <h4 class="text-xl font-semibold text-base-content transition-colors hover:text-primary">
                          {post.title}
                        </h4>

                        <p class="text-sm leading-6 text-muted">{post.excerpt}</p>

                        <.post_authors
                          :if={post[:authors] not in [nil, []]}
                          authors={post.authors}
                          links?={false}
                        />
                      </div>
                    </.link>
                  </article>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :post, :map, required: true
  attr :html, :string, default: nil
  attr :prev, :any, default: nil
  attr :next, :any, default: nil

  @doc """
  One blog post, with links to the neighbouring posts.

  Opens with the post's description, else its first paragraph in full (which
  `Gamend.Content.blog_post_html/1` has dropped from the body), then the
  cover when the body does not already show it. Whichever picture comes
  first, the cover or one the body opens with, is fetched first.
  """
  def blog_post(assigns) do
    cover = cover(assigns.post, assigns.html)

    assigns =
      assign(assigns,
        cover: cover,
        html: if(cover, do: assigns.html, else: eager_opening_image(assigns.html))
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="mx-auto max-w-narrow py-8">
        <article class="space-y-10">
          <div class="space-y-4">
            <%!-- Back to the blog, beside the date: the post's title is
                  too big to share a row with. --%>
            <div class="flex flex-wrap items-center gap-3">
              <.back_link href={
                GamendWeb.HostLayouts.localized_href(
                  "/blog",
                  GamendWeb.HostLayouts.current_locale()
                )
              } />
              <div class="flex flex-wrap items-center gap-3 text-xs uppercase tracking-[0.2em] text-muted">
                <span><.timestamp at={@post.date} format="date" /></span>
                <span :if={@post[:reading_minutes]}>
                  · {reading_time(@post.reading_minutes)}
                </span>
              </div>
            </div>

            <div class="space-y-3">
              <h1 class="text-4xl font-bold leading-tight text-base-content sm:text-5xl">
                {@post.title}
              </h1>
              <p class="max-w-2xl text-base leading-7 text-muted">{lede(@post)}</p>
              <.post_authors :if={@post[:authors] not in [nil, []]} authors={@post.authors} />
            </div>

            <img
              :if={@cover}
              src={@cover}
              alt=""
              fetchpriority="high"
              decoding="async"
              class="w-full rounded-2xl border border-base-300"
            />
          </div>

          <article class="markdown-content">{raw(@html)}</article>

          <%!-- `Content.blog_neighbours/1` walks a newest-first list, so `prev`
                is the NEWER post and `next` the older one. --%>
          <div class="grid gap-4 border-t border-base-300 pt-6 md:grid-cols-2">
            <div>
              <.link
                :if={@prev}
                navigate={~p"/blog/#{@prev.slug}"}
                class="group flex h-full flex-col rounded-2xl border border-base-300 bg-base-100/90 p-4 transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md"
              >
                <span class="text-xs uppercase tracking-[0.2em] text-muted">
                  {gettext("Newer")}
                </span>
                <span class="mt-2 text-lg font-semibold text-base-content group-hover:text-primary">
                  {@prev.title}
                </span>
              </.link>
            </div>
            <div>
              <.link
                :if={@next}
                navigate={~p"/blog/#{@next.slug}"}
                class="group flex h-full flex-col rounded-2xl border border-base-300 bg-base-100/90 p-4 text-right transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md"
              >
                <span class="text-xs uppercase tracking-[0.2em] text-muted">
                  {gettext("Older")}
                </span>
                <span class="mt-2 text-lg font-semibold text-base-content group-hover:text-primary">
                  {@next.title}
                </span>
              </.link>
            </div>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @doc """
  The picture to show above a post, or nil, at the URL the page serves it
  from (the blog's `:image_url` with `:page`, see `Gamend.Content.image_url/3`).

  The post's `image` is the card's and the link preview's. A post that also
  shows it in its body, as the same file or the same name in another format
  (`x.webp` for `x.png`), would show it twice, so the page leaves it to the
  body; a post with no frontmatter `image` took its picture from the body in
  the first place.
  """
  @spec cover(map(), String.t() | nil) :: String.t() | nil
  def cover(post, html) do
    case post[:image] do
      image when is_binary(image) and image != "" ->
        url = Content.image_url(:blog, image, :page)
        shown = for [_, src] <- Regex.scan(~r/<img[^>]+src="([^"]+)"/, html || ""), do: stem(src)
        if stem(url) in shown or stem(image) in shown, do: nil, else: url

      _ ->
        nil
    end
  end

  defp stem(src), do: src |> String.split(["?", "#"]) |> hd() |> Path.rootname()

  @doc """
  The body with the picture it opens with fetched first: `loading="eager"
  fetchpriority="high"` in place of the `lazy` every rendered image gets,
  when nothing but markup comes before it. With no cover above, that picture
  is the first thing a reader sees. A picture further down is left lazy.
  """
  @spec eager_opening_image(String.t() | nil) :: String.t() | nil
  def eager_opening_image(nil), do: nil

  def eager_opening_image(html) do
    with {start, _length} <- :binary.match(html, "<img"),
         "" <- Markdown.plain_text(binary_part(html, 0, start)) do
      Regex.replace(~r/<img\b[^>]*>/, html, &eager/1, global: false)
    else
      _later_or_none -> html
    end
  end

  defp eager(tag) do
    tag
    |> String.replace(~r/\s(loading|fetchpriority)="[^"]*"/, "")
    |> String.replace_prefix("<img", ~s(<img loading="eager" fetchpriority="high"))
  end

  # The lede above the body: the description when there is one, else the
  # first paragraph in full. The excerpt is that paragraph cut to 200
  # characters, and the body no longer holds the rest of it.
  defp lede(%{lede_in_body?: true, lede: lede}) when is_binary(lede) and lede != "", do: lede
  defp lede(post), do: post[:excerpt]

  defp card_image(post), do: post[:card_image] || post[:image]

  defp first_slug([{_year, [{_month, [post | _]} | _]} | _]), do: post[:slug]
  defp first_slug(_grouped_posts), do: nil

  # One number and an abbreviation, which no locale inflects, so one
  # translation rather than every locale's plural forms.
  defp reading_time(minutes), do: gettext("%{count} min read", count: minutes)

  attr :authors, :list, required: true
  attr :links?, :boolean, default: true

  # Who wrote it: a name, its role when the author file gives one, an avatar
  # when it gives that, and a link when it gives a URL. A post's `authors:`
  # keys that have no file still show as names. On an index card the whole
  # card is already a link, and a link inside a link is not HTML: the parser
  # closes the card's early and the text falls out of it. So `links?: false`
  # there, and the name links from the post itself.
  defp post_authors(assigns) do
    ~H"""
    <ul class="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
      <li :for={author <- @authors} class="flex items-center gap-2">
        <img
          :if={author[:image]}
          src={author.image}
          alt=""
          loading="lazy"
          class="size-7 rounded-full border border-base-300"
        />
        <span class="flex flex-col leading-tight">
          <a
            :if={@links? and author[:url]}
            href={author.url}
            class="font-medium link link-hover"
            rel="noopener"
          >
            {author.name}
          </a>
          <span :if={!(@links? and author[:url])} class="font-medium">{author.name}</span>
          <span :if={author[:title]} class="text-xs text-muted">{author.title}</span>
        </span>
      </li>
    </ul>
    """
  end

  attr :year, :integer, required: true
  attr :month, :integer, required: true

  # The month in the reader's language. This used to pass `Calendar.strftime`'s
  # English name through `dgettext` — but no catalog carries month names, so it
  # always came back in English while its comment said otherwise. The browser's
  # `Intl` already knows every locale's months: `local_time.js` translates this
  # with the zone pinned to UTC. Without JS the English name stands.
  defp month_heading(assigns) do
    assigns =
      assign(assigns,
        iso: "#{assigns.year}-#{String.pad_leading(to_string(assigns.month), 2, "0")}",
        english: Calendar.strftime(Date.new!(assigns.year, assigns.month, 1), "%B")
      )

    ~H"""
    <time datetime={@iso} data-local-time="calendar-month">{@english}</time>
    """
  end
end
