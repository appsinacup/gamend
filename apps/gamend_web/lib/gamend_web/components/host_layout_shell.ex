defmodule GamendWeb.HostLayoutShell do
  @moduledoc false

  use GamendWeb, :html

  alias Gamend.Accounts.Scope

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: ""
  attr :flush, :boolean, default: false
  attr :wide, :boolean, default: false
  attr :screen, :boolean, default: false
  attr :theme, :map, required: true
  attr :navigation, :map, default: %{}
  attr :footer, :map, default: %{}
  attr :background_icons, :list, default: []
  attr :notif_unread_count, :integer, default: 0
  attr :locale, :string, required: true
  attr :known_locales, :list, default: []
  attr :breadcrumbs, :list, default: []
  attr :search, :map, default: %{enabled: false, index_url: nil, query_url: nil}

  slot :inner_block, required: true

  def app(assigns) do
    # `nav_key` and `screen` are `Layouts.app`'s attrs; a shell rendered on
    # its own (a core template, a test) has neither. Put, not assigned:
    # nothing changes.
    assigns =
      assigns
      |> Map.put_new(:nav_key, nil)
      |> Map.put_new(:screen, false)
      |> assign(:side?, GamendWeb.HostLayoutNavigation.side_layout?(assigns[:navigation]))
      |> assign(:auto?, GamendWeb.HostLayoutNavigation.auto_layout?(assigns[:navigation]))

    ~H"""
    <%!-- First focusable element on every page: invisible until it receives
          keyboard focus, then lets the reader jump past the navbar straight
          to the main landmark. --%>
    <a
      href="#main-content"
      class="sr-only focus:not-sr-only focus:fixed focus:start-4 focus:top-4 focus:z-[200] focus:rounded-lg focus:bg-primary focus:px-4 focus:py-2 focus:font-semibold focus:text-primary-content focus:shadow-lg"
    >
      {GamendWeb.HostLayouts.translate("Skip to content")}
    </a>
    <.background_icons background_icons={@background_icons} />
    <%!-- The sidebar (`"layout": "sidebar"`) from `md` up, the page's column
          moved over by its width; the header keeps the rest. With `"layout":
          "auto"`, only where the bar does not fit (`[data-nav~=side]`,
          `navbar_fit.js`). --%>
    <GamendWeb.HostLayoutNavigation.side_nav
      :if={@side? or @auto?}
      auto={@auto?}
      current_scope={@current_scope}
      current_path={@current_path}
      navigation={@navigation}
      locale={@locale}
      nav_key={@nav_key}
      flush={@flush}
    >
      <:logo>
        <a
          href={GamendWeb.HostLayouts.localized_href(~p"/", @locale)}
          class="mb-2 flex items-center justify-center gap-2 rounded-field py-1.5 @min-[8rem]/side:justify-start @min-[8rem]/side:px-2"
        >
          <.site_mark theme={@theme} />
          <span class="text-lg font-bold leading-tight @max-[8rem]/side:sr-only">
            {Map.get(@theme, "title")}
          </span>
        </a>
      </:logo>
    </GamendWeb.HostLayoutNavigation.side_nav>
    <%!-- Below `md` the same links are a tab bar along the bottom; the column
          ends its height above it. --%>
    <GamendWeb.HostLayoutNavigation.tab_nav
      :if={@side? or @auto?}
      auto={@auto?}
      current_scope={@current_scope}
      current_path={@current_path}
      navigation={@navigation}
      locale={@locale}
      nav_key={@nav_key}
    />
    <div class={
      [
        "flex flex-col",
        if(@flush, do: "h-dvh overflow-hidden relative", else: "min-h-dvh"),
        # A one-screen page (`screen`) does not bounce at its ends, nor pull
        # to refresh: a tap that drags a little moves nothing.
        @screen && "[:root:has(&)]:overscroll-y-none",
        @side? && "max-md:pb-[calc(3.75rem+env(safe-area-inset-bottom))]",
        # The sidebar's room: the rail's on a full-screen page, else the open
        # sidebar's, or the rail's where the reader collapsed it.
        @side? && @flush && "md:ms-24 md:[--bleed-w:calc(100vw-6rem)]",
        (@side? or @auto?) &&
          "md:transition-[margin-inline-start] md:duration-(--motion-fold) md:ease-(--motion-out) motion-reduce:transition-none",
        @side? && !@flush &&
          "md:ms-56 md:[--bleed-w:calc(100vw-14rem)] md:[[data-side=rail]_&]:ms-24 md:[[data-side=rail]_&]:[--bleed-w:calc(100vw-6rem)]",
        # The same room, only while the sidebar shows (`"layout": "auto"`).
        @auto? && "max-md:[[data-nav~=side]_&]:pb-[calc(3.75rem+env(safe-area-inset-bottom))]",
        @auto? && @flush &&
          "md:[[data-nav~=side]_&]:ms-24 md:[[data-nav~=side]_&]:[--bleed-w:calc(100vw-6rem)]",
        @auto? && !@flush &&
          "md:[[data-nav~=side]_&]:ms-56 md:[[data-nav~=side]_&]:[--bleed-w:calc(100vw-14rem)] md:[[data-nav~=side][data-side=rail]_&]:ms-24 md:[[data-nav~=side][data-side=rail]_&]:[--bleed-w:calc(100vw-6rem)]"
      ]
    }>
      <div
        :if={@flush}
        id="navbar-autohide"
        phx-hook="NavbarAutohide"
        data-target="main-navbar"
        class="hidden"
      />
      <header
        id="main-navbar"
        phx-hook="NavbarDropdowns"
        class={
          [
            "navbar z-50 [[data-nav~=bar]_&]:gap-4",
            if(@flush,
              do: "absolute top-0 start-0 end-0 ps-4 sm:ps-6 lg:ps-8 pe-14",
              else: "sticky top-0 shrink-0 px-4 sm:px-6 lg:px-8"
            ),
            # The navigation's own surface (2026-10-23, user): a step off the
            # page, as the sidebar and the tab bar are, with a hairline under it.
            if(@flush,
              do: "bg-base-100/90 backdrop-blur-md",
              else: "bg-base-200/95 backdrop-blur-md border-b border-base-300"
            )
          ]
        }
      >
        <%!-- Read straight off `@theme` rather than through `<% var = ... %>`
              bindings: a variable defined in a template is opaque to change
              tracking, so the three of them re-rendered — and re-sent the
              logo's URL — on every diff the page sent, long after the theme
              stopped moving. --%>
        <%!-- A container as wide as the room the buttons leave: where that
              is too narrow for the title (a phone, 360 px), the title is
              screen-reader text and the logo stands alone, rather than the
              name spilling under the search button. --%>
        <%!-- The breadcrumb trail rides beside the name, so it costs the page
              no row of its own. Same container: the trail shows only while
              the room the buttons leave holds it (`breadcrumbs/1`). --%>
        <div class="@container min-w-0 flex-1 flex items-center gap-2">
          <a
            href={GamendWeb.HostLayouts.localized_href(~p"/", @locale)}
            data-nav-logo
            class={[
              "flex shrink-0 w-fit items-center gap-2",
              @side? && "md:hidden",
              @auto? && "md:[[data-nav~=side]_&]:hidden"
            ]}
          >
            <%!-- Same rule as `CoreComponents.flag/1`: this is on screen at
                  load on every page, so it is fetched with the HTML, decoded
                  with the first frame and prioritised over the ~45 flags the
                  locale dropdown queues behind it. Left async it painted a
                  beat after the title beside it on every refresh.

                  `alt=""` because it is decorative: the site name is the text
                  right beside it, so an alt repeating it makes a screen reader
                  say it twice — `image-redundant-alt`. The link is named by
                  that text. --%>
            <.site_mark theme={@theme} priority />
            <%!-- The title shows on a phone too (2026-10-09, user: the logo
                  alone left the bar empty). A two-word title fits a 375 px
                  phone's slot on two lines, and `leading-tight` keeps two
                  lines inside the bar's 4rem, so a page's sticky parts
                  (`top-16`) still sit under it. Only a slot under 8rem
                  keeps the logo alone. --%>
            <span class="text-lg font-bold leading-tight @max-[8rem]:sr-only">
              {Map.get(@theme, "title")}
            </span>
            <span
              :if={theme_tagline(@theme) && length(@breadcrumbs) < 2}
              class="text-sm opacity-80 ms-1 hidden [[data-nav~=labels]_&]:inline"
            >
              {theme_tagline(@theme)}
            </span>
          </a>
          <.breadcrumbs trail={@breadcrumbs} side={@side?} auto={@auto?} />
        </div>
        <%!-- The language picker sits outside both navs: one button in the bar
              at every width, rather than a dropdown up here and a different
              control buried in the phone menu. --%>
        <div data-nav-bar class="flex-none flex items-center gap-1 [[data-nav~=bar]_&]:gap-2">
          <GamendWeb.HostLayoutNavigation.desktop_nav
            current_scope={@current_scope}
            current_path={@current_path}
            current_query={@current_query}
            navigation={@navigation}
            notif_unread_count={@notif_unread_count}
            nav_key={@nav_key}
            locale={@locale}
            known_locales={@known_locales}
          />

          <%!-- One button at every width, like the language picker beside it:
                where the bar does not fit, the whole nav is a hamburger, so an
                input in the bar would be a desktop-only feature. The label is on `aria-label`
                and `title` rather than on screen — `title` and not a daisyUI
                `tooltip`, which hosts exclude from their stylesheet. --%>
          <button
            :if={@search.enabled}
            type="button"
            data-gamend-search-open
            aria-haspopup="dialog"
            aria-controls="gamend-search"
            aria-label={GamendWeb.HostLayouts.translate("Search")}
            title={GamendWeb.HostLayouts.translate("Search")}
            class="btn btn-ghost btn-circle"
          >
            <.icon name="hero-magnifying-glass-solid" class="w-5 h-5" />
          </button>

          <%!-- Last in the bar, after the nav. Where the bar does not fit, the
                phone bar's items join this row (`mobile_nav/1` is `contents`
                there) and the picker sits between its icons and the menu
                (2026-10-16, user: rightmost, but left of the menu). One
                picker in the page: its list of locales is not drawn twice.
                The order goes on the picker's button and dropdown, two
                levels down: both wrappers are `contents`. --%>
          <div :if={length(@known_locales) > 1} class="contents [&>*>*]:order-1">
            <GamendWeb.HostLayoutNavigation.language_dropdown
              locale={@locale}
              current_path={@current_path}
              current_query={@current_query}
              known_locales={@known_locales}
            />
          </div>

          <%!-- The account, rightmost where the bar is, as the menu is where
                it is not. --%>
          <GamendWeb.HostLayoutNavigation.desktop_account
            current_scope={@current_scope}
            current_path={@current_path}
            navigation={@navigation}
            notif_unread_count={@notif_unread_count}
            nav_key={@nav_key}
            locale={@locale}
          />

          <GamendWeb.HostLayoutNavigation.mobile_nav
            current_scope={@current_scope}
            current_path={@current_path}
            current_query={@current_query}
            navigation={@navigation}
            notif_unread_count={@notif_unread_count}
            nav_key={@nav_key}
            locale={@locale}
            known_locales={@known_locales}
          />
        </div>
      </header>

      <%!-- Outside `<header>` on purpose: the sheet is `position: fixed`, and
            the header's `backdrop-blur` makes it a containing block for fixed
            descendants — inside it, the sheet pins to the header's box and
            opens above the fold instead of along the bottom of the screen. --%>
      <GamendWeb.HostLayoutNavigation.language_modal
        :if={length(@known_locales) > 1}
        locale={@locale}
        current_path={@current_path}
        current_query={@current_query}
        known_locales={@known_locales}
      />

      <.search_dialog
        :if={@search.enabled}
        index_url={@search.index_url}
        query_url={@search[:query_url]}
      />

      <%= if @flush do %>
        <div id="main-content" class="flex-1 min-h-0 relative">
          {render_slot(@inner_block)}
        </div>
        <GamendWeb.HostLayouts.flash_group flash={@flash} />
      <% else %>
        <%!-- A one-screen page (`screen`) has no padding under its content:
              where the content nearly fit, the page scrolled into the
              padding, past the last thing on it. --%>
        <main
          id="main-content"
          class={[
            "relative z-[2] px-4 sm:px-6 lg:px-8 flex-1",
            if(@screen, do: "pt-4", else: "py-4")
          ]}
        >
          <%!-- Reading width by default. A `wide` page brings its own side
                columns — a docs sidebar, a table of contents — and the article
                between them is what should keep the reading width, so the
                frame lets it out to the screen. --%>
          <div class={[
            "mx-auto",
            if(@wide,
              do: "max-w-2xl md:max-w-3xl lg:max-w-5xl xl:max-w-7xl 2xl:max-w-screen-2xl",
              else: "max-w-2xl md:max-w-3xl lg:max-w-4xl xl:max-w-6xl"
            )
          ]}>
            <%!-- The page's own frame, applied here so no page has to know it:
                  one gap between blocks and one landing before the footer,
                  whichever repo wrote the page. A page that set its own `py-6`
                  used to sit lower than the page beside it in the nav, and
                  `pb-10` was on six pages and off the rest. `page-stack` is the
                  hook a host restyles; the utilities are the default. A
                  one-screen page (`screen`) has no footer, so no landing. --%>
            <div class={["page-stack space-y-6", !@screen && "pb-10"]}>
              <.suspended_notice :if={suspended?(@current_scope)} />
              {render_slot(@inner_block)}
            </div>
          </div>
        </main>

        <GamendWeb.HostLayouts.flash_group flash={@flash} />
        <footer :if={!@screen} class="px-4 py-8 sm:px-6 lg:px-8 text-sm text-muted">
          <div class="mx-auto grid max-w-2xl gap-6 md:max-w-3xl md:grid-cols-2 lg:max-w-4xl xl:max-w-6xl xl:grid-cols-4">
            <%!-- The column label is a `<p>`, not an `<h2>`: these name link
                  groups, not document sections, and as headings they were half
                  of every page's H2s — an outline where "Privacy & Terms" ranks
                  beside the page's actual subject. `aria-label` keeps the
                  grouping announced, which is what the heading was really
                  doing. --%>
            <div :for={section <- footer_sections(@footer)} class="space-y-2">
              <p class="text-sm font-semibold text-base-content">
                {section["title"]}
              </p>
              <nav aria-label={section["title"]} class="flex flex-col gap-1.5">
                <%= for link <- visible_footer_links(section, @current_scope) do %>
                  <span
                    :if={GamendWeb.HostLayoutNavigation.disabled?(link)}
                    aria-disabled="true"
                    class="inline-flex w-fit items-center gap-1.5 opacity-70"
                  >
                    {link["label"]}
                    <GamendWeb.HostLayoutNavigation.nav_badge entry={link} />
                  </span>
                  <a
                    :if={!GamendWeb.HostLayoutNavigation.disabled?(link)}
                    href={link["href"]}
                    target={if(link["external"], do: "_blank", else: nil)}
                    rel={if(link["external"], do: "noopener noreferrer", else: nil)}
                    class="inline-flex w-fit items-center gap-1.5 hover:text-base-content hover:underline"
                  >
                    {link["label"]}
                    <GamendWeb.HostLayoutNavigation.nav_badge entry={link} />
                  </a>
                <% end %>
              </nav>
            </div>
          </div>
        </footer>
      <% end %>
    </div>
    """
  end

  attr :index_url, :string, required: true

  attr :query_url, :string,
    default: nil,
    doc: "where to ask for rows the index cannot hold; absent when the host answers none"

  @doc """
  The site search palette.

  Server-rendered and empty: `search_palette.js` fills the list by cloning the
  two `<template>`s below. That split is deliberate — every class name stays
  in HEEx where Tailwind's scanner can see it (a class authored in a JS string
  is purged from the stylesheet), and the JS only ever sets `textContent`, so
  an entry's title cannot carry markup into the page.

  `phx-update="ignore"` because this lives inside the LiveView DOM: morphdom
  re-sends the layout on every diff and an open `<dialog>` has no `open`
  attribute in that markup, so the palette would close itself a second after
  opening on any page with a ticking clock. LiveView still syncs `data-*` on
  an ignored element, which is why the index URL travels as one and no client
  state does.
  """
  def search_dialog(assigns) do
    ~H"""
    <%!-- Outside `<header>` for the same reason the language sheet is, plus
          one of its own: on flush pages `NavbarAutohide` sets the header's
          `pointer-events: none`, and that inherits — a dialog inside it would
          be visible and unclickable. --%>
    <%!-- Not daisyUI's `.modal`: that centres its box in the viewport, and on a
          desktop the palette belongs under the button that opened it, not
          across the middle of the page. So the dialog positions itself —
          `search_palette.js` measures the button and writes `left`/`top`/
          `width` here — and these classes are the fallback it starts from and
          returns to on a narrow screen: a sheet along the top edge.

          `showModal()` still does the rest, which is why this stays a
          `<dialog>`: the top layer (no z-index to lose), Esc, the focus trap,
          and a real `::backdrop` whose clicks report the dialog itself as the
          target — which is how clicking outside closes it. --%>
    <dialog
      id="gamend-search"
      phx-update="ignore"
      data-gamend-search
      data-index-url={@index_url}
      data-query-url={@query_url}
      aria-labelledby="gamend-search-label"
      class="fixed inset-x-0 top-0 m-0 w-full max-w-none max-h-none border-0 bg-transparent p-2 backdrop:bg-base-300/50 sm:backdrop:bg-transparent"
    >
      <%!-- The panel, and the thing "outside" is measured against: a click
            that does not land inside it closes the palette. --%>
      <div
        data-gamend-search-panel
        class="mx-auto flex max-h-full w-full max-w-xl flex-col overflow-hidden rounded-box border border-base-300 bg-base-100 p-2 shadow-xl"
      >
        <h2 id="gamend-search-label" class="sr-only">
          {GamendWeb.HostLayouts.translate("Search")}
        </h2>

        <.search_input
          id="gamend-search-input"
          label={GamendWeb.HostLayouts.translate("Search")}
          data-gamend-search-input
          role="combobox"
          aria-expanded="false"
          aria-controls="gamend-search-results"
          aria-autocomplete="list"
          close={%{"data-gamend-search-close" => true}}
          close_label={GamendWeb.HostLayouts.translate("Close")}
        />

        <%!-- `flex-nowrap`: daisyUI's `.menu` is `column wrap`, so a capped
              height wraps into a second column off to the side instead of
              scrolling.

              `w-full min-w-0`: `.menu` is also `width: fit-content`, which is
              right for a dropdown that hugs its items and wrong for a list
              inside a fixed-width panel — it grew to the widest row (1260px
              in a 576px box) and every row hung out over the right edge.
              `min-w-0` is what then lets a long title actually truncate
              instead of pushing the row back out again. --%>
        <ul
          id="gamend-search-results"
          data-gamend-search-results
          role="listbox"
          aria-label={GamendWeb.HostLayouts.translate("Search")}
          hidden
          class="menu menu-sm mt-2 max-h-[60vh] min-h-0 w-full min-w-0 flex-1 flex-nowrap overflow-y-auto overflow-x-hidden overscroll-contain p-0"
        >
        </ul>

        <p data-gamend-search-empty hidden class="px-3 py-4 text-sm text-muted">
          {GamendWeb.HostLayouts.translate("No results.")}
        </p>

        <template data-gamend-search-group>
          <li class="menu-title px-3 pt-3 pb-1 text-xs uppercase tracking-wide">
            <span data-group-label></span>
          </li>
        </template>

        <template data-gamend-search-row>
          <li class="w-full min-w-0">
            <a
              role="option"
              class="flex w-full min-w-0 items-center justify-between gap-3 rounded-lg px-3 py-2"
            >
              <span data-row-title class="min-w-0 truncate font-semibold"></span>
              <span data-row-subtitle class="min-w-0 truncate text-xs text-muted"></span>
            </a>
          </li>
        </template>
      </div>
    </dialog>
    """
  end

  attr :trail, :list, default: []
  attr :side, :boolean, default: false, doc: "the host's sidebar is on (`side_nav/1`)"
  attr :auto, :boolean, default: false, doc: "the sidebar is on where the bar does not fit"

  @doc """
  The breadcrumb trail, as `{label, path}` pairs — the last one is the current
  page and carries a `nil` path.

  Renders nothing for a bare `[{"Home", nil}]`: a trail with no ancestors tells
  the reader nothing, and Google ignores a single-item `BreadcrumbList`.

  Drawn in the navbar, after the site name, so the first crumb (the home page)
  is left out: the name beside it is that link. One line: where the trail is
  longer than the room, its EARLIEST crumbs go, whole, and the page's own
  stay. A crumb cut to a few letters each (`Dicti… / Spa… / Pe…`) said
  nothing. The line is filled from the current page backwards (`order`, laid
  out `flex-row-reverse`), and what does not fit wraps to a second line the
  `h-5` clips. The markup keeps the trail's order, so a screen reader hears
  all of it. A crumb alone on the line and still too long is cut short, its
  full name on `title`.

  Shown only where there is room for it. Not on a phone (below `sm`), and not
  while the navbar's buttons leave its container narrower than `22rem`: from
  `xl` the whole nav is in the bar, and the trail comes back from about
  1440 px. Below that the page's own heading (its Back, its menus) is the way
  up.

  `config :gamend_web, :breadcrumb_depth, n` draws only a trail of `n` crumbs
  or more past home (default 1): where the navigation lights the section and
  the heading names the rest, a two-crumb trail only repeats them. The trail
  itself is unchanged, so its `BreadcrumbList` markup is too.
  """
  def breadcrumbs(assigns) do
    assigns = assign(assigns, :crumbs, assigns.trail |> Enum.drop(1) |> Enum.with_index())
    assigns = assign(assigns, :last, length(assigns.crumbs) - 1)

    assigns =
      assign(assigns, :depth, max(Application.get_env(:gamend_web, :breadcrumb_depth, 1), 1))

    ~H"""
    <nav
      :if={length(@crumbs) >= @depth}
      aria-label={GamendWeb.HostLayouts.translate("Breadcrumb")}
      class="hidden min-w-0 text-sm text-muted sm:flex @max-[22rem]:hidden"
    >
      <ol class="flex h-5 min-w-0 flex-row-reverse flex-wrap items-center justify-end gap-x-2 overflow-hidden">
        <li
          :for={{{label, path}, index} <- @crumbs}
          class="flex min-w-0 items-center gap-2"
          style={"order: #{@last - index}"}
        >
          <%!-- The first follows the site's name; with the sidebar, from
                `md` up the name is the sidebar's and the trail starts the
                bar. --%>
          <span
            aria-hidden="true"
            class={[
              "shrink-0",
              (@side and index == 0) && "md:hidden",
              (@auto and index == 0) && "md:[[data-nav~=side]_&]:hidden"
            ]}
          >
            /
          </span>
          <.link
            :if={path}
            href={path}
            title={label}
            class="truncate hover:text-primary transition-colors"
          >
            {label}
          </.link>
          <span
            :if={is_nil(path)}
            aria-current="page"
            title={label}
            class="truncate text-base-content"
          >
            {label}
          </span>
        </li>
      </ol>
    </nav>
    """
  end

  attr :theme, :map, required: true

  attr :priority, :boolean,
    default: false,
    doc: "the header's: fetched first, decoded with the first frame"

  # The site's mark: the theme's logo, and its `logo_dark` in its place on a
  # dark page. The header's and the sidebar's.
  defp site_mark(assigns) do
    ~H"""
    <img
      src={theme_logo(@theme)}
      width="36"
      height="36"
      alt=""
      loading="eager"
      decoding="sync"
      fetchpriority={@priority && "high"}
      class={theme_logo_dark(@theme) && "[[data-theme=dark]_&]:hidden"}
    />
    <%!-- A mark drawn for a light page can vanish on a dark one. The
          theme's `logo_dark` takes its place, swapped by the same
          attribute the presentation images follow, so no script picks
          one and the two never both show. --%>
    <img
      :if={theme_logo_dark(@theme)}
      src={theme_logo_dark(@theme)}
      width="36"
      height="36"
      alt=""
      loading="eager"
      decoding="sync"
      class="hidden [[data-theme=dark]_&]:block"
    />
    """
  end

  defp theme_logo(theme) do
    logo = Map.get(theme, "logo")
    GamendWeb.SRI.versioned_path(logo) || logo
  end

  defp theme_logo_dark(theme) do
    case Map.get(theme, "logo_dark") do
      logo when is_binary(logo) and logo != "" -> GamendWeb.SRI.versioned_path(logo) || logo
      _ -> nil
    end
  end

  defp theme_tagline(theme) do
    case Map.get(theme, "tagline") do
      tagline when is_binary(tagline) and tagline != "" -> tagline
      _ -> nil
    end
  end

  defp footer_sections(%{"sections" => sections}) when is_list(sections), do: sections
  defp footer_sections(_footer), do: []

  # A footer link obeys the same `"auth"` rule as the nav: /store is behind
  # `require_authenticated_user`, so advertising it to a signed-out visitor
  # just sends them to an error.
  # A banned account (`Gamend.Bans`) is sent to /suspended from every LiveView
  # (`GamendWeb.UserAuth`); a plain page shows it this, which leads there. An
  # ETS read, no query.
  defp suspended?(current_scope) do
    case Scope.user_id(current_scope) do
      user_id when is_binary(user_id) -> Gamend.Bans.banned?(:account, user_id)
      _ -> false
    end
  end

  defp suspended_notice(assigns) do
    ~H"""
    <.link href={~p"/suspended"} id="suspended-notice" class="alert alert-warning" role="status">
      <.icon name="hero-no-symbol" class="size-5" />
      <span>{GamendWeb.HostLayouts.translate("Account suspended")}</span>
    </.link>
    """
  end

  defp visible_footer_links(section, current_scope) do
    section
    |> Map.get("links", [])
    |> Enum.filter(&GamendWeb.HostLayoutNavigation.entry_visible?(&1, current_scope))
  end

  attr :background_icons, :list, default: []

  @doc """
  The shell's decorative icon layer.

  Which pages get one is decided in `GamendWeb.HostLayouts`: it hands over an
  empty list for pages that paint their own. Faint, 4% light and 5% dark
  (2026-10-23, Polyglot Pirates: at 8% and 10% they showed through every
  card and row and read as clutter); the home's layer
  (`GamendWeb.PresentationPage`) is the same.
  """
  def background_icons(assigns) do
    ~H"""
    <%= if @background_icons != [] do %>
      <div class="fixed inset-0 overflow-hidden pointer-events-none z-[1]" aria-hidden="true">
        <%= for placement <- GamendWeb.HostLayouts.icon_placements(@background_icons) do %>
          <div
            class={[
              "absolute text-base-content [[data-theme=dark]_&]:text-white opacity-[0.04] [[data-theme=dark]_&]:opacity-[0.05]",
              placement.size
            ]}
            style={"top: #{placement.top}%; #{if Map.has_key?(placement, :left), do: "left: #{placement.left}%", else: "right: #{placement.right}%"}; animation: float #{placement.dur}s ease-in-out infinite #{placement.delay}s;"}
          >
            <.dynamic_icon name={placement.name} class={placement.size} />
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
