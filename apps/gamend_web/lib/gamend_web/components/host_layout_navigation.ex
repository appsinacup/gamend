defmodule GamendWeb.HostLayoutNavigation do
  @moduledoc false

  use GamendWeb, :html

  alias Gamend.Accounts.Scope
  alias GamendWeb.Plugs.LocalePath

  # What the bar has room for is measured, not guessed from a breakpoint
  # (`navbar_fit.js`): `<html data-nav>` names what shows, "bar labels name"
  # down to "bar", else the menu. Each word is a class's condition.
  defp fit_label, do: "[html:not([data-nav~=labels])_&]:sr-only"
  defp fit_name, do: "[html:not([data-nav~=name])_&]:[&>*+*]:sr-only"

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: ""
  attr :navigation, :map, default: %{}
  attr :notif_unread_count, :integer, default: 0
  attr :locale, :string, required: true
  attr :known_locales, :list, default: []

  attr :nav_key, :any,
    default: nil,
    doc:
      "what the page changes that an entry shows (`Layouts.app`'s): a change re-renders the bar, since no other attr of it moves"

  def desktop_nav(assigns) do
    assigns = prepare_navigation_assigns(assigns)

    # With the sidebar (`side_nav/1`) the bar keeps only what the sidebar
    # does not draw: an entry the host draws (a wallet), a readonly badge, a
    # group. Below `md` there is no sidebar, and `navbar_fit.js` keeps the
    # phone's menu there whatever fits. With `"layout": "auto"` the bar has
    # every link, and the sidebar's go where the sidebar shows
    # (`[data-nav~=side]`).
    assigns =
      if assigns.side?,
        do: update(assigns, :primary_links, &Enum.reject(&1, fn entry -> side_link?(entry) end)),
        else: assigns

    # The theme toggle is set apart from the links before it, when any are
    # drawn: the bar's settings and account end (`desktop_account/1`) follow.
    # With `"layout": "auto"` a sidebar link leaves the bar while the sidebar
    # shows, so a divider after nothing else goes with them.
    others = if(assigns.current_scope, do: assigns.authenticated_links, else: assigns.guest_links)
    stays? = others != [] or Enum.any?(assigns.primary_links, &(not side_link?(&1)))

    assigns =
      assign(assigns,
        links?: assigns.primary_links != [] or others != [],
        divider_class: assigns.auto? and not stays? and "[[data-nav~=side]_&]:hidden"
      )

    ~H"""
    <ul class="hidden [[data-nav~=bar]_&]:flex flex-row px-1 space-x-4 items-center">
      <.main_nav_links
        links={@primary_links}
        current_path={@current_path}
        inactive_class="btn-surface"
        side={@auto?}
      />

      <%= if @current_scope do %>
        <%= if @authenticated_links != [] do %>
          <.nav_divider />
          <.main_nav_links
            links={@authenticated_links}
            current_path={@current_path}
            inactive_class="btn-surface"
          />
        <% end %>
      <% else %>
        <%= if @guest_links != [] do %>
          <.nav_divider />
          <.main_nav_links
            links={@guest_links}
            current_path={@current_path}
            inactive_class="btn-surface"
          />
        <% end %>
      <% end %>

      <%!-- The language picker is NOT here: the shell renders it once, outside
            both layouts. A copy per layout puts the ~30 locale entries into the
            page twice — 26 KB of a 77 KB document — and a test asserts each
            locale link appears exactly once. It therefore sits to the right of
            this toggle rather than left of it, as it used to. --%>
      <.nav_divider :if={@links?} class={@divider_class} />
      <li>
        <GamendWeb.HostLayouts.theme_toggle />
      </li>
    </ul>
    """
  end

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :navigation, :map, default: %{}
  attr :notif_unread_count, :integer, default: 0
  attr :locale, :string, required: true

  attr :nav_key, :any,
    default: nil,
    doc: "as `desktop_nav/1`'s: what the page changes that an entry shows (a count)"

  @doc """
  The bar's account end, drawn by the shell after the language picker
  (2026-10-23, user: the account rightmost, as the phone's menu is): the
  reader's menu, or Log in and Register. Shown where the bar is
  (`[data-nav~=bar]`); elsewhere they are the menu's (`mobile_nav/1`).
  """
  def desktop_account(assigns) do
    assigns = prepare_navigation_assigns(assigns)
    assigns = assign(assigns, :guest?, Scope.anonymous?(assigns.current_scope))

    ~H"""
    <%!-- `order-2`: the language picker before it is ordered `1` (the shell). --%>
    <ul class="hidden [[data-nav~=bar]_&]:flex order-2 flex-row space-x-4 items-center">
      <%!-- Log in and Register, each its own button wherever the bar shows
            (2026-10-23, user): a dropdown hid the two things a visitor came
            to press. A guest account gets the same two and no avatar: an
            avatar beside Log in said both "you are in" and "sign in", and
            Register keeps what is on the account. --%>
      <.auth_buttons :if={is_nil(@current_scope) or @guest?} current_path={@current_path} />
      <li :if={@current_scope && !@guest?}>
        <.user_menu
          current_scope={@current_scope}
          current_path={@current_path}
          notif_unread_count={@notif_unread_count}
          account_links={@account_links}
        />
      </li>
    </ul>
    """
  end

  attr :current_scope, :map, required: true
  attr :current_path, :string, default: nil
  attr :notif_unread_count, :integer, default: 0
  attr :account_links, :list, default: []

  def user_menu(assigns) do
    path = assigns.current_path

    assigns =
      assign(assigns,
        active?:
          any_entry_active?(assigns.account_links, path) or here?(path, "/users/settings") or
            here?(path, "/notifications") or here?(path, "/chat"),
        anonymous?: Scope.anonymous?(assigns.current_scope)
      )

    ~H"""
    <details class="dropdown dropdown-end" data-navbar-dropdown>
      <summary
        title={display_name(Scope.user(@current_scope))}
        class={["btn gap-1 list-none", if(@active?, do: "btn-primary", else: "btn-surface")]}
      >
        <%!-- The player card (`player_card/1`), as every list draws the
              player: on a filled button its line takes the button's colour. --%>
        <.player_card
          user={Scope.user(@current_scope)}
          name={display_name(Scope.user(@current_scope))}
          size="sm"
          subtitle_class={if(@active?, do: nil, else: "text-muted")}
          class={["max-w-[10rem]", fit_name()]}
        />
        <.count_pill count={@notif_unread_count} />
        <.icon name="hero-chevron-down-solid" class="w-3 h-3" />
      </summary>
      <ul class="menu menu-sm dropdown-content mt-2 z-[1] p-2 shadow-lg bg-base-100 rounded-box w-56">
        <%!-- The nearest thing the site has to a profile card: who you are,
              and the game's own line under it (a rank, when the host stamps
              one) — the same title that shows under this player everywhere
              else, so it is not a surprise to see it here. --%>
        <li class="menu-title px-2 py-1">
          <span class="flex flex-col leading-tight text-base-content">
            <.player_name
              name={display_name(Scope.user(@current_scope))}
              class="max-w-full font-semibold"
            />
            <.user_title user={Scope.user(@current_scope)} />
            <span :if={@anonymous?} class="text-xs font-normal text-muted">
              {GamendWeb.HostLayouts.translate("Guest")}
            </span>
          </span>
        </li>
        <li>
          <.link
            href={lp(~p"/users/settings")}
            class={[
              if(here?(@current_path, "/users/settings"), do: "menu-active", else: "")
            ]}
          >
            <.icon name="hero-user-circle-solid" class="w-4 h-4" />
            {GamendWeb.HostLayouts.translate("Account")}
          </.link>
        </li>
        <.dropdown_menu_entries entries={@account_links} current_path={@current_path} />

        <li>
          <.link
            href={lp(~p"/notifications")}
            class={[
              if(here?(@current_path, "/notifications"), do: "menu-active", else: "")
            ]}
          >
            <.icon name="hero-bell-solid" class="w-4 h-4" />
            {GamendWeb.HostLayouts.translate("Notifications")}
            <.count_pill count={@notif_unread_count} />
          </.link>
        </li>
        <li :if={GamendWeb.Features.enabled?(:web_chat)}>
          <.link
            href={lp(~p"/chat")}
            class={[if(here?(@current_path, "/chat"), do: "menu-active", else: "")]}
          >
            <.icon name="hero-chat-bubble-left-right-solid" class="w-4 h-4" />
            {GamendWeb.HostLayouts.translate("Chat")}
          </.link>
        </li>
        <%!-- A guest account has no way back in once its session is gone, so
              it is never offered Log out. `desktop_nav/1` draws a guest no
              menu at all: Log in and Register are its buttons
              (`auth_buttons/1`). --%>
        <li :if={!@anonymous?} class="border-t border-base-300 mt-1 pt-1">
          <.link href={~p"/users/log_out"} method="delete">
            <.icon name="hero-arrow-left-on-rectangle-solid" class="w-4 h-4" />
            {GamendWeb.HostLayouts.translate("Log out")}
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: ""
  attr :navigation, :map, default: %{}
  attr :notif_unread_count, :integer, default: 0
  attr :locale, :string, required: true
  attr :known_locales, :list, default: []

  attr :nav_key, :any,
    default: nil,
    doc:
      "what the page changes that an entry shows (`Layouts.app`'s): a change re-renders the bar, since no other attr of it moves"

  def mobile_nav(assigns) do
    assigns = prepare_navigation_assigns(assigns)

    # With the sidebar its links are the sidebar's, and on a phone the tab
    # bar's (`tab_nav/1`): neither pinned nor in the menu. With `"layout":
    # "auto"` the menu shows only with the sidebar (`navbar_fit.js`), so the
    # same.
    primary_links =
      if assigns.side? or assigns.auto?,
        do: Enum.reject(assigns.primary_links, &side_link?/1),
        else: assigns.primary_links

    # Items flagged "mobile": "pinned" render inline (left of the hamburger)
    # instead of inside the dropdown, so they stay visible on mobile.
    pinned = Enum.filter(primary_links ++ assigns.authenticated_links, &pinned_link?/1)

    assigns =
      assign(assigns,
        pinned_links: pinned,
        primary_links: Enum.reject(primary_links, &pinned_link?/1),
        authenticated_links: Enum.reject(assigns.authenticated_links, &pinned_link?/1)
      )

    # On a phone every count is behind the hamburger, so it shows their total.
    menu_count =
      if(assigns.current_scope, do: assigns.notif_unread_count, else: 0) +
        Enum.sum(
          Enum.map(
            assigns.primary_links ++ assigns.authenticated_links ++ assigns.account_links,
            &Map.get(&1, "count", 0)
          )
        )

    assigns = assign(assigns, :menu_count, menu_count)

    ~H"""
    <%!-- `contents` where the bar does not fit: its icons and its menu are
          items of the bar's row, so the site language's picker (ordered `1`)
          sits between them and the menu (ordered `2`). --%>
    <%!-- With the sidebar, the menu button stays where the bar does not fit
          from `md` up, and is always the phone's (`navbar_fit.js`); what is
          pinned there is the host's own entries (a wallet). --%>
    <div class="contents [[data-nav~=bar]_&]:hidden">
      <.mobile_pinned_links links={@pinned_links} current_path={@current_path} />
      <details class="dropdown dropdown-end order-2" data-navbar-dropdown>
        <summary
          aria-label={GamendWeb.HostLayouts.translate("Open navigation menu")}
          class={[
            "btn btn-ghost list-none relative",
            if(@menu_button == "account", do: "btn-circle", else: "px-1")
          ]}
        >
          <.count_pill count={@menu_count} class="absolute -top-1 -end-1" />
          <%!-- `"menu_button": "account"`: the menu opens from the reader
                (their avatar, a person for a visitor), the account being
                the menu's first section. --%>
          <%= if @menu_button == "account" do %>
            <.user_avatar
              :if={@current_scope}
              user={Scope.user(@current_scope)}
              class="size-8"
            />
            <.icon :if={!@current_scope} name="hero-user-circle" class="size-8" />
          <% else %>
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 6h16M4 12h16M4 18h16"
              >
              </path>
            </svg>
          <% end %>
        </summary>
        <%!-- The menu is taller than a phone once the Learn/Social/News groups
              and the account section are expanded, and a dropdown does not
              scroll on its own: the overflowing items were simply unreachable.
              Cap it to the viewport (dvh, so the mobile URL bar collapsing does
              not cut it off) and scroll inside. `overscroll-contain` keeps the
              scroll from continuing into the page behind it.

              `grid` is also what makes the cap scroll instead of reflow:
              daisyUI's `.menu` is `flex-flow: column wrap`, so a max-height on
              its own wrapped the items into a SECOND COLUMN off to the side —
              vertically unscrollable and horizontally clipped, which is worse
              than the overflow it was meant to fix.

              The rows are left-aligned in ONE centred column: the track is as
              wide as the widest row (`fit-content`, never past the panel), and
              at least 12.5rem (the widest row in any locale: Russian, 197px), so
              opening a group with a longer label does not shift the column
              sideways. --%>
        <ul class="menu menu-sm dropdown-content mt-3 z-[1] max-h-[calc(100dvh-5rem)] grid grid-cols-[fit-content(100%)] justify-center content-start *:min-w-50 overflow-y-auto overflow-x-hidden overscroll-contain px-5 py-4 shadow bg-base-100 rounded-box w-72 text-lg">
          <%= if @current_scope do %>
            <.mobile_account_menu
              current_scope={@current_scope}
              current_path={@current_path}
              notif_unread_count={@notif_unread_count}
              account_links={@account_links}
            />

            <.mobile_nav_links
              links={@primary_links ++ @authenticated_links}
              current_path={@current_path}
              inactive_class="btn-ghost"
              group="mobile-nav"
            />
          <% else %>
            <.mobile_nav_links
              links={@guest_links}
              current_path={@current_path}
              inactive_class="btn-ghost"
              group="mobile-nav"
            />

            <li>
              <a
                href={lp(~p"/users/log_in")}
                class={[
                  "btn w-full justify-start",
                  if(here?(@current_path, "/users/log_in"),
                    do: "btn-primary",
                    else: "btn-ghost"
                  )
                ]}
              >
                <.icon name="hero-arrow-right-on-rectangle-solid" class="w-4 h-4" />
                {GamendWeb.HostLayouts.translate("Log in")}
              </a>
            </li>
            <li :if={GamendWeb.Features.enabled?(:web_registration)}>
              <a
                href={lp(~p"/users/register")}
                class={[
                  "btn w-full justify-start",
                  if(here?(@current_path, "/users/register"),
                    do: "btn-primary",
                    else: "btn-ghost"
                  )
                ]}
              >
                <.icon name="hero-user-plus-solid" class="w-4 h-4" />
                {GamendWeb.HostLayouts.translate("Register")}
              </a>
            </li>

            <.mobile_nav_links
              links={@primary_links}
              current_path={@current_path}
              inactive_class="btn-ghost"
              group="mobile-nav"
            />
          <% end %>

          <%!-- The language picker lives in the header bar beside this menu,
                rendered once for both layouts — see `desktop_nav/1`. --%>
          <li class="mt-2">
            <div class="flex justify-start">
              <GamendWeb.HostLayouts.theme_toggle />
            </div>
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :navigation, :map, default: %{}
  attr :locale, :string, required: true

  attr :nav_key, :any,
    default: nil,
    doc: "as `desktop_nav/1`'s: what the page changes that an entry shows (a count)"

  attr :flush, :boolean, default: false, doc: "a full-screen page: the rail, never open"

  attr :auto, :boolean,
    default: false,
    doc: "`\"layout\": \"auto\"`: shown only where the bar does not fit (`[data-nav~=side]`)"

  slot :logo, required: true, doc: "the site's mark and name, linking home (the shell's)"

  @doc """
  The sidebar (`"layout": "sidebar"`, 2026-10-22): the host's plain primary
  links down the page's start edge from `md` up, each its icon and its label.
  Open (14rem, the label beside the icon) at every width it shows (user,
  2026-10-23: spelled out, never icons alone); the rail (6rem, the label
  under the icon) on a full-screen page and where the reader collapsed it. The button at its foot sets `<html data-side="rail">`, which
  this browser keeps and sets again before the next page paints
  (`side_nav.js`, from `theme-init.js`), as it does the theme. The button is
  its chevron alone, turning with the state; the width moves over the host's
  `--motion-fold`, as the page's margin does (`HostLayoutShell`). An item lays
  itself out by the sidebar's width (a container query), so both states are
  one markup. A link's `"tone"` colours its icon and the page's own tint
  (`tone/1`). Groups, drawn entries and readonly badges stay in the bar
  (`desktop_nav/1`). With `"layout": "auto"` (`auto`) it shows only where
  the bar holds no stage (`auto_layout?/1`).
  """
  def side_nav(assigns) do
    assigns = prepare_navigation_assigns(assigns)
    links = Enum.filter(assigns.primary_links, &side_link?/1)
    assigns = assign(assigns, links: links, best_href: best_href(links, assigns.current_path))

    ~H"""
    <nav
      id="side-nav"
      class={[
        "@container/side fixed inset-y-0 start-0 z-40 hidden flex-col gap-1 w-24",
        if(@auto, do: "md:[[data-nav~=side]_&]:flex", else: "md:flex"),
        "overflow-y-auto overflow-x-hidden overscroll-contain border-e border-base-300 bg-base-200 px-1.5 py-3",
        "transition-[width] duration-(--motion-fold) ease-(--motion-out) motion-reduce:transition-none",
        !@flush && "md:w-56 md:[[data-side=rail]_&]:w-24"
      ]}
    >
      {render_slot(@logo)}
      <.side_nav_item
        :for={link <- @links}
        link={link}
        active?={sibling_active?(link, @current_path, @best_href)}
      />
      <button
        :if={!@flush}
        type="button"
        data-side-toggle
        class={[
          "mt-auto flex items-center justify-center rounded-field px-1 py-2",
          "text-muted hover:bg-base-100 @min-[8rem]/side:justify-start @min-[8rem]/side:px-3"
        ]}
      >
        <.icon
          name="hero-chevron-left-solid"
          class="size-5 shrink-0 rtl:-scale-x-100 motion-ease [[data-side=rail]_&]:rotate-180"
        />
        <span class="sr-only [[data-side=rail]_&]:hidden">
          {GamendWeb.HostLayouts.translate("Collapse")}
        </span>
        <span class="hidden [[data-side=rail]_&]:inline sr-only">
          {GamendWeb.HostLayouts.translate("Expand")}
        </span>
      </button>
    </nav>
    """
  end

  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :navigation, :map, default: %{}
  attr :locale, :string, required: true

  attr :nav_key, :any,
    default: nil,
    doc: "as `desktop_nav/1`'s: what the page changes that an entry shows (a count)"

  attr :auto, :boolean, default: false, doc: "as `side_nav/1`'s"

  @doc """
  The sidebar's phone form (`"layout": "sidebar"`, 2026-10-22): the same
  links in a bar along the bottom of the screen below `md`, one tab each, the
  icon over its label. The shell pads the page by its height, so nothing ends
  under it. A link marked `"mobile": "hidden"` is the sidebar's only: a
  phone's bar has room for so many tabs, and its section's pages light the
  link that also claims them (its `"active"` prefixes). With `"layout":
  "auto"` (`auto`), only where the bar does not fit the phone.
  """
  def tab_nav(assigns) do
    assigns = prepare_navigation_assigns(assigns)
    links = Enum.filter(assigns.primary_links, &(side_link?(&1) and not phone_hidden?(&1)))
    assigns = assign(assigns, links: links, best_href: best_href(links, assigns.current_path))

    ~H"""
    <nav
      id="tab-nav"
      class={
        [
          "fixed inset-x-0 bottom-0 z-40",
          if(@auto, do: "hidden max-md:[[data-nav~=side]_&]:flex", else: "flex md:hidden"),
          # Each tab its label on one line, so the bar is one row (user,
          # 2026-10-26: "Word games" on two lines made the bar a line
          # taller); the room left is shared out evenly, and a label is cut
          # short only where the tabs cannot all fit (`side_nav_item/1`).
          "border-t border-base-300 bg-base-200 pt-1 pb-[calc(0.25rem+env(safe-area-inset-bottom))]"
        ]
      }
    >
      <.side_nav_item
        :for={link <- @links}
        link={link}
        compact
        active?={sibling_active?(link, @current_path, @best_href)}
      />
    </nav>
    """
  end

  attr :link, :map, required: true
  attr :active?, :boolean, default: false
  attr :compact, :boolean, default: false, doc: "the tab bar's cell: smaller words, less room"

  # One sidebar link, and one tab of the tab bar: in the rail the label under
  # the icon, small, wrapping; in the tab bar under it on one line, the tab
  # as wide as its label and the room left shared out; open, beside it, cut
  # where it does not fit. The count sits on the icon's corner under it, at
  # the row's end beside it. The layout follows the sidebar's width
  # (`@container/side`); the tab bar is no such container, so its tabs are
  # the rail's.
  defp side_nav_item(assigns) do
    ~H"""
    <a
      href={if(disabled?(@link), do: nil, else: @link["href"])}
      target={if(@link["external"], do: "_blank", else: nil)}
      rel={if(@link["external"], do: "noopener noreferrer", else: nil)}
      aria-current={if(@active?, do: "page")}
      aria-disabled={if(disabled?(@link), do: "true")}
      data-tone={tone(@link)}
      class={
        [
          "relative flex flex-col items-center rounded-field",
          # A tab's edge is drawn inside it: a border's 2 px a tab cut every
          # Spanish label short on a 360 px phone (2026-10-26).
          if(@compact, do: "ring-inset", else: "border"),
          "text-center font-semibold leading-tight transition-colors",
          if(@compact,
            do: "min-w-0 flex-auto gap-0.5 px-0 py-1.5 text-[10px] tracking-tight",
            else: "gap-1 px-0.5 py-2 text-[11px]"
          ),
          "@min-[8rem]/side:flex-row @min-[8rem]/side:gap-3 @min-[8rem]/side:px-3",
          "@min-[8rem]/side:text-start @min-[8rem]/side:text-sm",
          cond do
            disabled?(@link) -> "border-transparent pointer-events-none opacity-70"
            @active? and tone(@link) != nil and @compact -> [tone_active(), tone_ring()]
            @active? and tone(@link) != nil -> tone_active()
            @active? -> "border-transparent bg-primary text-primary-content"
            true -> "border-transparent hover:bg-base-100"
          end
        ]
      }
    >
      <.icon :if={@link["icon"]} name={@link["icon"]} class={icon_class(@link, "size-6 shrink-0")} />
      <span class={[
        "min-w-0 max-w-full @min-[8rem]/side:flex-1 @min-[8rem]/side:truncate",
        if(@compact, do: "truncate", else: "line-clamp-2 break-words hyphens-auto")
      ]}>
        {translate_label(@link["label"])}
      </span>
      <span class="hidden @min-[8rem]/side:contents"><.nav_badge entry={@link} /></span>
      <.count_pill
        count={@link["count"]}
        class="absolute top-0.5 end-1 @min-[8rem]/side:static"
      />
    </a>
    """
  end

  attr :locale, :string, required: true
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: ""
  attr :known_locales, :list, default: []

  @doc """
  The language picker's button(s).

  Two controls, one visible at a time, mirroring the in-page language selector
  (the host's in-page selector) so the site opens a language list
  the same way everywhere:

    * from `sm` up, a `<details>` dropdown like every other navbar menu;
    * below it, a button opening the bottom sheet `language_modal/1` renders.

  A phone gets a sheet rather than a panel because a dropdown is positioned
  against its *button*, and the globe is not the last thing in the bar — the
  hamburger is. Any panel wide enough to be useful therefore starts off the left
  edge of the screen.

  This does mean the ~30 locale entries are in the document twice, about 13 KB.
  The sheet is why: it is `position: fixed`, and the header's `backdrop-blur`
  makes the header a containing block for fixed descendants, so the sheet has to
  live outside the header while the dropdown lives inside it.
  """
  def language_dropdown(assigns) do
    assigns =
      assign(assigns,
        label: locale_label(assigns.locale),
        flag_code: locale_flag(assigns.locale, locale_flags?()),
        locale_links:
          locale_links(assigns.current_path, assigns.current_query, assigns.known_locales)
      )

    ~H"""
    <div class="contents">
      <%!-- `priority`: this flag is in the header of every page, so a lazy one
            pops in after the label on each refresh, and a merely eager one
            queues behind whatever that page is full of. --%>
      <%!-- The flag alone at every width (user, 2026-10-23: the language's
            name cost the bar its links' words), one icon, so `btn-ghost`,
            and as narrow as the bar's icons. Less after the chevron, which
            the menu button follows. The name is screen-reader text and the
            hover's `title`. --%>
      <label
        for="lang-modal"
        title={@label}
        class="btn gap-1 ps-2 pe-1 list-none btn-ghost cursor-pointer sm:hidden"
      >
        <.locale_mark flag_code={@flag_code} label={@label} />
        <.icon name="hero-chevron-down-solid" class="w-3 h-3" />
      </label>

      <details class="dropdown dropdown-end hidden sm:block" data-navbar-dropdown>
        <summary title={@label} class="btn btn-ghost gap-1 ps-2 pe-1 list-none">
          <.locale_mark flag_code={@flag_code} label={@label} />
          <.icon name="hero-chevron-down-solid" class="w-3 h-3" />
        </summary>

        <%!-- Four columns at most: "Espa\u00f1ol" and "Espa\u00f1ol (Espa\u00f1a)" truncate to
              the same string in five, which makes them impossible to tell apart.

              Deliberately not daisyUI's `menu menu-sm` like the sibling panels:
              `.menu li` is `display:flex` and its `> a` will not shrink below
              its content, so long labels ("Portugu\u00eas do Brasil") burst out of
              their grid track and over the next column. `menu` is built for a
              vertical list; this is a grid, and it only needs the surface. --%>
        <ul class="dropdown-content z-[100] mt-2 grid max-h-[70vh] w-[min(78vw,44rem)] grid-cols-3 gap-1 overflow-y-auto rounded-box bg-base-100 p-2 shadow-lg lg:grid-cols-4">
          <.locale_option :for={link <- @locale_links} link={link} locale={@locale} />
        </ul>
      </details>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: ""
  attr :known_locales, :list, default: []

  @doc """
  The phone-sized language picker: a bottom sheet, like the in-page selector's.

  Rendered by the shell **outside** `<header>`. It is `position: fixed`, and the
  header's `backdrop-blur` would make the header its containing block — the
  sheet would then pin to the header's box and open above the fold instead of
  along the bottom of the screen.
  """
  def language_modal(assigns) do
    assigns =
      assign(assigns,
        label: locale_label(assigns.locale),
        locale_links:
          locale_links(assigns.current_path, assigns.current_query, assigns.known_locales)
      )

    ~H"""
    <%!-- The checkbox is only a state holder — the visible labels toggle it.
          Without tabindex="-1" it is a Tab stop (daisyUI hides it with
          `opacity: 0`, not `display: none`), and on desktop it was the page's
          *first* one: an invisible control receiving focus. --%>
    <input
      type="checkbox"
      id="lang-modal"
      class="peer modal-toggle sm:hidden"
      tabindex="-1"
      aria-label={GamendWeb.HostLayouts.translate("Choose language")}
    />
    <%!-- `peer` + `content-visibility`: a closed daisyUI modal is only
          `visibility: hidden`, so its subtree is still laid out and every flag
          in it is fetched on page load for a sheet nobody opened. Skipping the
          subtree outright is what stops that; it renders normally the moment
          the toggle is checked. --%>
    <div
      class="modal modal-bottom z-[100] peer-[:not(:checked)]:[content-visibility:hidden] sm:hidden"
      role="dialog"
    >
      <div class="modal-box max-w-2xl p-3">
        <div class="flex items-center justify-between gap-3">
          <h3 class="flex items-center gap-2 text-sm font-black uppercase tracking-[0.12em]">
            <.icon name="hero-globe-alt-solid" class="w-4 h-4" />
            {@label}
          </h3>
          <%!-- The name is text: a `<label>` may not carry `aria-label`. --%>
          <label for="lang-modal" class="btn btn-ghost btn-square btn-sm">
            <span class="sr-only">
              {GamendWeb.HostLayouts.translate("Close language picker")}
            </span>
            <.icon name="hero-x-mark-solid" class="size-4" />
          </label>
        </div>

        <%!-- Same rule as the in-page selector: fit as many tiles as there is
              room for, rather than a fixed column count that squeezes them. --%>
        <ul class="mt-3 grid max-h-[60vh] grid-cols-[repeat(auto-fit,minmax(7rem,1fr))] gap-1 overflow-y-auto">
          <.locale_option :for={link <- @locale_links} link={link} locale={@locale} />
        </ul>
      </div>
      <label class="modal-backdrop" for="lang-modal">
        {GamendWeb.HostLayouts.translate("Close")}
      </label>
    </div>
    """
  end

  attr :link, :map, required: true
  attr :locale, :string, required: true

  # One row, shared by the dropdown and the sheet so they cannot drift apart.
  # `min-w-0` on both the item and the anchor: a grid track and a flex item each
  # default to min-content width, so without it the longest label ("Portugu\u00eas do
  # Brasil") pushes its column over the next one instead of letting `truncate` do
  # its job.
  #
  # The current locale is a solid `bg-primary` with its paired content color:
  # the previous primary-tinted text on a primary-tinted fill fell below AA
  # contrast on themed hosts.
  defp locale_option(assigns) do
    ~H"""
    <li class="min-w-0 list-none">
      <%!-- `data-no-live-nav`: a language switch is the HTTP request that
            `LocalePath` reads (`?setlang=`, a new prefix). Moved over the
            socket, `/x?setlang=en` from an unprefixed page in another
            language would mount in the language being left. --%>
      <a
        href={@link.href}
        rel={@link[:rel]}
        data-no-live-nav
        aria-current={if(@link.locale == @locale, do: "true")}
        class={[
          "flex min-w-0 items-center gap-2 rounded px-2 py-2 text-sm transition-colors",
          if(@link.locale == @locale,
            do: "bg-primary font-semibold text-primary-content",
            else: "hover:bg-base-200"
          )
        ]}
      >
        <%!-- `deferred`: this row is in the document ~30 times over, in a
              dropdown and a sheet that are both closed. --%>
        <.flag
          :if={@link.flag_code}
          code={@link.flag_code}
          deferred
          class="rounded-[2px] shadow-sm ring-1 ring-base-content/10"
        />
        <span class="truncate">{@link.label}</span>
      </a>
    </li>
    """
  end

  attr :links, :list, default: []
  attr :current_path, :string, default: nil
  attr :inactive_class, :string, required: true

  attr :side, :boolean,
    default: false,
    doc: "`\"layout\": \"auto\"`: a sidebar link leaves the bar while the sidebar shows"

  defp main_nav_links(assigns) do
    assigns = assign(assigns, :best_href, best_href(assigns.links, assigns.current_path))

    ~H"""
    <%= for entry <- @links do %>
      <li class={@side && side_link?(entry) && "[[data-nav~=side]_&]:hidden"}>
        <.main_nav_link_item
          link={entry}
          current_path={@current_path}
          best_href={@best_href}
          inactive_class={@inactive_class}
        />
      </li>
    <% end %>
    """
  end

  attr :links, :list, default: []
  attr :current_path, :string, default: nil
  attr :inactive_class, :string, required: true
  attr :group, :string, default: nil

  defp mobile_nav_links(assigns) do
    assigns = assign(assigns, :best_href, best_href(assigns.links, assigns.current_path))

    ~H"""
    <%= for entry <- @links do %>
      <li class="w-full">
        <.mobile_nav_link_item
          link={entry}
          current_path={@current_path}
          best_href={@best_href}
          inactive_class={@inactive_class}
          group={@group}
        />
      </li>
    <% end %>
    """
  end

  attr :links, :list, default: []
  attr :current_path, :string, default: nil

  # Compact inline buttons for "mobile": "pinned" leaf links, shown left of the
  # hamburger. Icon + (possibly dynamic) label, no dropdown wrapping. A link
  # with an icon shows the icon alone, its label for a screen reader and on
  # hover: five pinned sections fit a phone's bar as icons, not as words. A
  # readonly entry (a coin balance) keeps its label: the number is the point.
  # An entry the host draws (`"render"`) is drawn as it draws it, `:pinned`.
  defp mobile_pinned_links(assigns) do
    ~H"""
    <%= for link <- @links do %>
      <%= if rendered?(link) do %>
        {link["render_fun"].(:pinned)}
      <% else %>
        <a
          href={if(inert?(link), do: nil, else: link["href"])}
          title={if(icon_only?(link), do: translate_label(link["label"]))}
          aria-disabled={if(inert?(link), do: "true")}
          data-motion-text={if(readonly?(link), do: "pop")}
          data-tone={tone(link)}
          class={
            cond do
              readonly?(link) ->
                "inline-flex items-center gap-1 px-2 pointer-events-none cursor-default"

              disabled?(link) ->
                "btn btn-ghost btn-sm gap-1 px-2 pointer-events-none cursor-default opacity-70"

              # The page's own link is `btn-primary` (or its tone's tint), as
              # on the desktop bar.
              true ->
                [
                  "btn btn-sm gap-1 px-2",
                  state_class(link, entry_active?(link, @current_path), "btn-ghost")
                ]
            end
          }
        >
          <.icon :if={link["icon"]} name={link["icon"]} class={icon_class(link)} />
          <span class={["text-sm font-semibold", icon_only?(link) && "sr-only"]}>
            {translate_label(link["label"])}
          </span>
          <.nav_badge entry={link} />
          <.count_pill count={link["count"]} />
        </a>
      <% end %>
    <% end %>
    """
  end

  # A leaf link (not a dropdown group) explicitly pinned outside the mobile menu.
  defp pinned_link?(entry) do
    Map.get(entry, "mobile") == "pinned" and not dropdown_entry?(entry)
  end

  # A link left out of the phone's tab bar (`tab_nav/1`).
  defp phone_hidden?(entry), do: Map.get(entry, "mobile") == "hidden"

  # A link that can be drawn as its icon (a phone's bar, or the desktop bar
  # without its labels): one with an icon that is not a readonly badge.
  defp icon_only?(entry), do: is_binary(entry["icon"]) and not readonly?(entry)

  attr :current_scope, :map, required: true
  attr :current_path, :string, default: nil
  attr :notif_unread_count, :integer, default: 0
  attr :account_links, :list, default: []

  # Mobile account section: collapsible group headed by the user's name (like
  # the desktop user menu). Holds Account, Notifications, Chat (unless
  # `web_chat` is off), then the config account_links (admin items) last,
  # then Log out.
  defp mobile_account_menu(assigns) do
    active? =
      account_path_active?(assigns.current_path, "/users/settings") or
        account_path_active?(assigns.current_path, "/notifications") or
        account_path_active?(assigns.current_path, "/chat") or
        any_entry_active?(assigns.account_links, assigns.current_path)

    assigns =
      assign(assigns,
        active?: active?,
        anonymous?: Scope.anonymous?(assigns.current_scope),
        register?: GamendWeb.Features.enabled?(:web_registration)
      )

    ~H"""
    <li class="w-full">
      <details open={@active?} name="mobile-nav" class="group w-full">
        <summary class={[
          "btn w-full justify-start pe-10 relative cursor-pointer list-none summary-no-marker",
          if(@active?, do: "btn-primary", else: "btn-ghost")
        ]}>
          <span class="flex min-w-0 items-center gap-2">
            <.player_card
              user={Scope.user(@current_scope)}
              name={display_name(Scope.user(@current_scope))}
              size="sm"
              subtitle_class={if(@active?, do: nil, else: "text-muted")}
            />
            <.count_pill count={@notif_unread_count} class="ms-0.5" />
          </span>
          <.icon
            name="hero-chevron-down-solid"
            class="w-3 h-3 absolute end-4 transition-transform group-open:rotate-180"
          />
        </summary>
        <ul class="mt-1">
          <li class="w-full">
            <a
              href={lp(~p"/users/settings")}
              class={[
                "btn w-full justify-start",
                account_item_class(@current_path, "/users/settings")
              ]}
            >
              <.icon name="hero-user-circle-solid" class="w-4 h-4" />
              {GamendWeb.HostLayouts.translate("Account")}
            </a>
          </li>
          <li class="w-full">
            <a
              href={lp(~p"/notifications")}
              class={["btn w-full justify-start", account_item_class(@current_path, "/notifications")]}
            >
              <.icon name="hero-bell-solid" class="w-4 h-4" />
              {GamendWeb.HostLayouts.translate("Notifications")}
              <.count_pill count={@notif_unread_count} class="ms-0.5" />
            </a>
          </li>
          <li :if={GamendWeb.Features.enabled?(:web_chat)} class="w-full">
            <a
              href={lp(~p"/chat")}
              class={["btn w-full justify-start", account_item_class(@current_path, "/chat")]}
            >
              <.icon name="hero-chat-bubble-left-right-solid" class="w-4 h-4" />
              {GamendWeb.HostLayouts.translate("Chat")}
            </a>
          </li>
          <.mobile_nav_links
            links={@account_links}
            current_path={@current_path}
            inactive_class="btn-ghost"
          />
          <%!-- Without `web_registration` a guest registers in the game, and
                Log in opens the section instead. --%>
          <%= if @anonymous? do %>
            <li :if={@register?} class="border-t border-base-300 mt-1 pt-1 w-full">
              <a href={lp(~p"/users/register")} class="btn btn-ghost w-full justify-start">
                <.icon name="hero-user-plus-solid" class="w-4 h-4" />
                {GamendWeb.HostLayouts.translate("Register")}
              </a>
            </li>
            <li class={["w-full", !@register? && "border-t border-base-300 mt-1 pt-1"]}>
              <a href={lp(~p"/users/log_in")} class="btn btn-ghost w-full justify-start">
                <.icon name="hero-arrow-right-on-rectangle-solid" class="w-4 h-4" />
                {GamendWeb.HostLayouts.translate("Log in")}
              </a>
            </li>
          <% else %>
            <li class="border-t border-base-300 mt-1 pt-1 w-full">
              <.link
                href={~p"/users/log_out"}
                method="delete"
                class="btn btn-ghost w-full justify-start"
              >
                <.icon name="hero-arrow-left-on-rectangle-solid" class="w-4 h-4" />
                {GamendWeb.HostLayouts.translate("Log out")}
              </.link>
            </li>
          <% end %>
        </ul>
      </details>
    </li>
    """
  end

  defp account_path_active?(current_path, prefix), do: here?(current_path || "", prefix)

  defp account_item_class(current_path, prefix) do
    if account_path_active?(current_path, prefix), do: "btn-primary", else: "btn-ghost"
  end

  attr :link, :map, required: true
  attr :current_path, :string, default: nil
  attr :inactive_class, :string, required: true
  attr :best_href, :string, default: nil

  defp main_nav_link_item(assigns) do
    active? = sibling_active?(assigns.link, assigns.current_path, assigns[:best_href])
    icon_only? = icon_only?(assigns.link)

    # A label beside an icon goes where the bar is too narrow for it, and is
    # the tooltip then.
    assigns =
      assign(assigns,
        active?: active?,
        label_class: if(icon_only?, do: fit_label()),
        title: if(icon_only?, do: translate_label(assigns.link["label"]))
      )

    ~H"""
    <%= if dropdown_entry?(@link) do %>
      <details class="dropdown" data-navbar-dropdown>
        <summary
          title={@title}
          data-tone={tone(@link)}
          class={["btn list-none", state_class(@link, @active?, @inactive_class)]}
        >
          <.icon :if={@link["icon"]} name={@link["icon"]} class={icon_class(@link)} />
          <span class={@label_class}>{translate_label(@link["label"])}</span>
          <.count_pill count={@link["count"]} />
          <.icon name="hero-chevron-down-solid" class="w-3 h-3" />
        </summary>
        <ul class="menu menu-sm dropdown-content mt-2 z-[1] p-2 shadow-lg bg-base-100 rounded-box w-64">
          <.dropdown_menu_entries entries={@link["items"]} current_path={@current_path} />
        </ul>
      </details>
    <% else %>
      <%= if rendered?(@link) do %>
        {@link["render_fun"].(:desktop)}
      <% else %>
        <a
          href={if(inert?(@link), do: nil, else: @link["href"])}
          target={if(@link["external"], do: "_blank", else: nil)}
          rel={if(@link["external"], do: "noopener noreferrer", else: nil)}
          aria-disabled={if(inert?(@link), do: "true")}
          data-motion-text={if(readonly?(@link), do: "pop")}
          data-tone={tone(@link)}
          title={@title}
          class={
            cond do
              readonly?(@link) ->
                "inline-flex items-center gap-2 px-2 pointer-events-none cursor-default"

              disabled?(@link) ->
                ["btn pointer-events-none cursor-default opacity-70", @inactive_class]

              true ->
                ["btn", state_class(@link, @active?, @inactive_class)]
            end
          }
        >
          <.icon :if={@link["icon"]} name={@link["icon"]} class={icon_class(@link)} />
          <span class={@label_class}>{translate_label(@link["label"])}</span>
          <.nav_badge entry={@link} />
          <.count_pill count={@link["count"]} />
        </a>
      <% end %>
    <% end %>
    """
  end

  attr :link, :map, required: true
  attr :current_path, :string, default: nil
  attr :inactive_class, :string, required: true
  attr :best_href, :string, default: nil

  # `group` is the top-level groups' shared `<details name>`: the browser keeps
  # one of them open, so opening Social closes Learn and the rest stay on a
  # phone's screen. Nested groups get none — one sharing its parent's name
  # would close the parent it sits in.
  attr :group, :string, default: nil

  defp mobile_nav_link_item(assigns) do
    active? = sibling_active?(assigns.link, assigns.current_path, assigns[:best_href])

    assigns = assign(assigns, active?: active?)

    ~H"""
    <%= if dropdown_entry?(@link) do %>
      <details open={@active?} name={@group} class="group w-full">
        <summary
          data-tone={tone(@link)}
          class={[
            "btn w-full justify-start pe-10 relative cursor-pointer list-none summary-no-marker",
            state_class(@link, @active?, @inactive_class)
          ]}
        >
          <span class="flex items-center gap-2">
            <.icon :if={@link["icon"]} name={@link["icon"]} class={icon_class(@link)} />
            <span>{translate_label(@link["label"])}</span>
            <.count_pill count={@link["count"]} />
          </span>
          <.icon
            name="hero-chevron-down-solid"
            class="w-3 h-3 absolute end-4 transition-transform group-open:rotate-180"
          />
        </summary>
        <ul class="mt-1">
          <.mobile_nav_links
            links={@link["items"]}
            current_path={@current_path}
            inactive_class={@inactive_class}
          />
        </ul>
      </details>
    <% else %>
      <%= if rendered?(@link) do %>
        {@link["render_fun"].(:menu)}
      <% else %>
        <a
          href={if(inert?(@link), do: nil, else: @link["href"])}
          target={if(@link["external"], do: "_blank", else: nil)}
          rel={if(@link["external"], do: "noopener noreferrer", else: nil)}
          aria-disabled={if(inert?(@link), do: "true")}
          data-motion-text={if(readonly?(@link), do: "pop")}
          data-tone={tone(@link)}
          class={
            cond do
              readonly?(@link) ->
                "inline-flex items-center gap-2 px-2 w-full pointer-events-none cursor-default"

              disabled?(@link) ->
                [
                  "btn w-full justify-start pointer-events-none cursor-default opacity-70",
                  @inactive_class
                ]

              true ->
                ["btn w-full justify-start", state_class(@link, @active?, @inactive_class)]
            end
          }
        >
          <.icon :if={@link["icon"]} name={@link["icon"]} class={icon_class(@link)} />
          {translate_label(@link["label"])}
          <.nav_badge entry={@link} />
          <.count_pill count={@link["count"]} />
        </a>
      <% end %>
    <% end %>
    """
  end

  attr :entries, :list, default: []
  attr :current_path, :string, default: nil

  defp dropdown_menu_entries(assigns) do
    assigns = assign(assigns, :best_href, best_href(assigns.entries, assigns.current_path))

    ~H"""
    <%= for entry <- @entries do %>
      <.dropdown_menu_entry entry={entry} current_path={@current_path} best_href={@best_href} />
    <% end %>
    """
  end

  attr :entry, :map, required: true
  attr :current_path, :string, default: nil
  attr :best_href, :string, default: nil

  defp dropdown_menu_entry(assigns) do
    active? = sibling_active?(assigns.entry, assigns.current_path, assigns[:best_href])

    assigns = assign(assigns, active?: active?)

    ~H"""
    <%= if dropdown_entry?(@entry) do %>
      <li>
        <details open={@active?}>
          <summary data-tone={tone(@entry)} class={[if(@active?, do: "menu-active", else: "")]}>
            <.icon :if={@entry["icon"]} name={@entry["icon"]} class={icon_class(@entry)} />
            {translate_label(@entry["label"])}
            <.count_pill count={@entry["count"]} />
          </summary>
          <ul>
            <.dropdown_menu_entries entries={@entry["items"]} current_path={@current_path} />
          </ul>
        </details>
      </li>
    <% else %>
      <li>
        <a
          href={if(inert?(@entry), do: nil, else: @entry["href"])}
          target={if(@entry["external"], do: "_blank", else: nil)}
          rel={if(@entry["external"], do: "noopener noreferrer", else: nil)}
          aria-disabled={if(inert?(@entry), do: "true")}
          data-tone={tone(@entry)}
          class={[
            if(@active?, do: "menu-active", else: ""),
            if(inert?(@entry), do: "pointer-events-none cursor-default"),
            if(disabled?(@entry), do: "opacity-70")
          ]}
        >
          <.icon :if={@entry["icon"]} name={@entry["icon"]} class={icon_class(@entry)} />
          {translate_label(@entry["label"])}
          <.nav_badge entry={@entry} />
          <.count_pill count={@entry["count"]} />
        </a>
      </li>
    <% end %>
    """
  end

  defp prepare_navigation_assigns(assigns) do
    scope = assigns.current_scope
    auth_level = auth_level(Scope.user(scope))

    entries = fn key, default_auth ->
      assigns.navigation
      |> section_entries(key, auth_level, default_auth, scope)
      |> Enum.map(&resolve_entry_count(&1, scope))
      |> Enum.map(&resolve_entry_href(&1, scope, assigns[:current_path], assigns[:locale]))
      |> Enum.map(&resolve_entry_render(&1, scope, assigns[:current_path], assigns[:nav_key]))
    end

    assign(assigns,
      primary_links: entries.("primary_links", "any"),
      guest_links: entries.("guest_links", "unauthenticated"),
      authenticated_links: entries.("authenticated_links", "authenticated"),
      account_links: entries.("account_links", "authenticated"),
      side?: side_layout?(assigns.navigation),
      auto?: auto_layout?(assigns.navigation),
      menu_button: Map.get(assigns.navigation, "menu_button", "menu")
    )
  end

  @doc """
  Whether the host's navigation is the sidebar (`"layout": "sidebar"`):
  `side_nav/1` from `md` up, the bar below it.
  """
  def side_layout?(navigation) when is_map(navigation),
    do: Map.get(navigation, "layout") == "sidebar"

  def side_layout?(_navigation), do: false

  @doc """
  Whether the host's navigation is the bar while it fits, else the sidebar
  (`"layout": "auto"`, 2026-10-23): every link in the bar where one of its
  stages fits the window, and where none does, the sidebar from `md` up and
  the tab bar below it, the bar keeping the rest. `navbar_fit.js` decides,
  and says so with `side` in `<html data-nav>`; every part that shows with
  the sidebar shows under `[data-nav~=side]`, not a breakpoint alone.
  """
  def auto_layout?(navigation) when is_map(navigation),
    do: Map.get(navigation, "layout") == "auto"

  def auto_layout?(_navigation), do: false

  # What the sidebar draws: a plain link. A group, an entry the host draws
  # and a readonly badge stay in the bar.
  defp side_link?(entry),
    do: not dropdown_entry?(entry) and not rendered?(entry) and not readonly?(entry)

  # An entry's `"count"`: a `{Module.fun}` token that resolves to a number of
  # things waiting for the viewer there (quests to claim), drawn as the same
  # pill as the unread notifications. A group shows its items' total, so a
  # count inside a closed dropdown still shows on the dropdown. Resolved here
  # and not in `section_entries/5`, which `flat_links/2` shares: a search
  # index has no use for the numbers and should not pay for them.
  defp resolve_entry_count(%{"items" => items} = entry, scope) when is_list(items) do
    items = Enum.map(items, &resolve_entry_count(&1, scope))

    entry
    |> Map.put("items", items)
    |> Map.put("count", Enum.sum(Enum.map(items, &Map.get(&1, "count", 0))))
  end

  defp resolve_entry_count(%{"count" => token} = entry, scope) when is_binary(token) do
    count =
      case token |> resolve_dynamic_tokens(scope) |> String.trim() |> Integer.parse() do
        {n, ""} when n > 0 -> n
        _ -> 0
      end

    Map.put(entry, "count", count)
  end

  defp resolve_entry_count(entry, _scope), do: Map.delete(entry, "count")

  # An entry's `"href"` as a `{Module.fun}` token: the function is given the
  # scope and the current path (arity 2) and answers the path to link, which
  # then takes the reader's locale prefix the way a configured path does. For
  # a link whose target depends on the reader: a host's "Word games" that
  # opens the language the reader is on, or the one they opened last. A
  # group's items resolve too. Resolved here, beside the counts, for the
  # same reason: a search index has no reader to resolve them for.
  defp resolve_entry_href(%{"items" => items} = entry, scope, current_path, locale)
       when is_list(items) do
    Map.put(entry, "items", Enum.map(items, &resolve_entry_href(&1, scope, current_path, locale)))
  end

  defp resolve_entry_href(%{"href" => "{" <> _ = token} = entry, scope, current_path, locale) do
    href =
      case token
           |> String.trim("{")
           |> String.trim("}")
           |> String.trim()
           |> resolve_token([scope, current_path]) do
        "" -> "/"
        path -> GamendWeb.HostLayouts.localized_href(path, locale)
      end

    Map.put(entry, "href", href)
  end

  defp resolve_entry_href(entry, _scope, _current_path, _locale), do: entry

  # An entry's `"render"`: a `{Module.fun}` token naming a host function
  # component that draws the whole entry (a wallet of two balances, each a
  # link), given `%{scope, current_path, variant}`: `:desktop` on the wide
  # bar, `:pinned` in a phone's bar (`"mobile": "pinned"`), `:menu` in its
  # menu. The host owns the markup, the bar where it goes. Resolved here
  # into a function of the variant, since the three places draw one entry;
  # a token that names nothing draws nothing. A `"label"` is still required
  # (`valid_link?/1`), and `"readonly": true` keeps it out of the search
  # index (`flat_links/2`), since it is not a place to go.
  # `nav_key` rides in the closure on purpose: two closures over the same
  # values are equal, so an entry whose function captured only the scope and
  # the path never read as changed, and the bar kept the first render (a
  # wallet's km stood still after the round that earned them). With the
  # page's `nav_key` captured, the entry changes when it does.
  defp resolve_entry_render(%{"render" => "{" <> _ = token} = entry, scope, current_path, nav_key) do
    name = token |> String.trim("{") |> String.trim("}") |> String.trim()

    Map.put(entry, "render_fun", fn variant ->
      render_token(name, %{
        scope: scope,
        current_path: current_path,
        variant: variant,
        nav_key: nav_key
      })
    end)
  end

  defp resolve_entry_render(entry, _scope, _current_path, _nav_key), do: entry

  defp render_token(name, assigns) do
    {fun_str, mod_parts} = name |> String.split(".") |> List.pop_at(-1)

    with false <- mod_parts == [],
         module = Module.concat(mod_parts),
         true <- Code.ensure_loaded?(module),
         fun = String.to_atom(fun_str),
         true <- function_exported?(module, fun, 1) do
      apply(module, fun, [assigns])
    else
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp rendered?(entry), do: is_function(Map.get(entry, "render_fun"), 1)

  defp section_entries(navigation, key, auth_level, default_auth, scope) do
    navigation
    |> Map.get(key, [])
    |> Enum.map(&normalize_navigation_entry(&1, auth_level, default_auth, scope))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_navigation_entry(%{"items" => items} = entry, auth_level, default_auth, scope)
       when is_list(items) do
    visible_items =
      items
      |> Enum.map(&normalize_navigation_entry(&1, auth_level, default_auth, scope))
      |> Enum.reject(&is_nil/1)

    if valid_group?(entry) and visible_items != [] and
         link_visible?(entry, auth_level, default_auth) do
      entry
      |> Map.put("items", visible_items)
      |> resolve_entry_label(scope)
    end
  end

  defp normalize_navigation_entry(entry, auth_level, default_auth, scope) do
    if valid_link?(entry) and link_visible?(entry, auth_level, default_auth) do
      resolve_entry_label(entry, scope)
    end
  end

  # Resolves {Module.Func} tokens in a nav entry's label. Each token calls the
  # named function (arity 1, given the current scope) and substitutes its
  # stringified result; the config is host-authored, and resolution is guarded
  # (only already-loaded module/atoms, failures render as empty). Labels
  # without a token are untouched (translation happens later at render).
  defp resolve_entry_label(%{"label" => label} = entry, scope) when is_binary(label) do
    if String.contains?(label, "{") do
      Map.put(entry, "label", resolve_dynamic_tokens(label, scope))
    else
      entry
    end
  end

  defp resolve_entry_label(entry, _scope), do: entry

  defp resolve_dynamic_tokens(label, scope) do
    Regex.replace(~r/\{([^{}]+)\}/, label, fn _match, token ->
      resolve_token(String.trim(token), [scope])
    end)
  end

  # `args` is what the provider is called with: the scope for a label or a
  # count, the scope and the current path for an href.
  defp resolve_token(token, args) do
    parts = String.split(token, ".")
    {fun_str, mod_parts} = List.pop_at(parts, -1)

    # Build + load the module rather than String.to_existing_atom: the provider
    # module is named only in trusted config (never referenced as a literal in
    # code), so its atom/beam may not be loaded yet in this process.
    with false <- mod_parts == [],
         module = Module.concat(mod_parts),
         true <- Code.ensure_loaded?(module),
         fun = String.to_atom(fun_str),
         true <- function_exported?(module, fun, length(args)) do
      module |> apply(fun, args) |> to_string()
    else
      _ -> ""
    end
  rescue
    _ -> ""
  catch
    _, _ -> ""
  end

  defp valid_group?(%{"label" => label, "items" => items}) do
    is_binary(label) and label != "" and is_list(items)
  end

  defp valid_group?(_entry), do: false

  defp valid_link?(%{"label" => label} = entry) do
    is_binary(label) and label != "" and
      (inert?(entry) or (is_binary(entry["href"]) and entry["href"] != ""))
  end

  defp valid_link?(_link), do: false

  # A display-only item ("readonly": true) renders as a non-interactive badge
  # (icon + label, no href/click) — e.g. a live status/value indicator. It
  # carries `data-motion-text="pop"`: a host's motion script plays a pop when
  # its value changes on the page (a coin balance a claim or a purchase
  # moved); without one the attribute does nothing.
  defp readonly?(entry), do: Map.get(entry, "readonly") == true

  # A link to something announced and not there yet ("disabled": true): drawn
  # as the link, never followed, usually with a `"badge"` ("Coming soon").
  @doc false
  def disabled?(entry), do: Map.get(entry, "disabled") == true

  defp inert?(entry), do: readonly?(entry) or disabled?(entry)

  attr :entry, :map, required: true

  @doc """
  An entry's `"badge"`: a short tag after its label ("Pro", "Coming soon").
  Shared by the nav and the footer.
  """
  def nav_badge(assigns) do
    ~H"""
    <span
      :if={is_binary(@entry["badge"]) and @entry["badge"] != ""}
      class="badge badge-xs badge-primary whitespace-nowrap"
    >
      {translate_label(@entry["badge"])}
    </span>
    """
  end

  attr :count, :any, default: 0
  attr :class, :string, default: nil

  # The red number on the nav: unread notifications, an entry's `"count"`
  # (quests to claim). Nothing at zero.
  defp count_pill(assigns) do
    ~H"""
    <span
      :if={is_integer(@count) and @count > 0}
      class={[
        "inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1 text-xs font-bold rounded-full bg-error text-error-content",
        @class
      ]}
    >
      {@count}
    </span>
    """
  end

  @doc """
  Whether `entry` should be shown to a viewer with this `current_scope`.

  Same `"auth"` convention the nav uses (`"any"`, `"unauthenticated"`,
  `"authenticated"`, `"admin"`, or `"admin_only": true`), exposed so the footer
  filters identically — a link to a page the viewer cannot open is a link to an
  error page.
  """
  @spec entry_visible?(map(), map() | nil) :: boolean()
  def entry_visible?(entry, current_scope) do
    link_visible?(entry, auth_level(Scope.user(current_scope)), "any")
  end

  @doc """
  Every navigation destination this viewer can reach, as a flat list.

  What the nav renders as four sections of groups and leaves, the search
  palette needs as rows: `%{title, href, group}`, where `group` is the
  dropdown the link lives in, or nil for a top-level link.

  It goes through `section_entries/5` rather than `entry_visible?/2` because
  each section has its own default for an entry that does not declare `auth` —
  an account link with no `auth` is for signed-in readers, and filtering it
  with the public "any" default would offer admin pages to a stranger.

  Dynamic `{Module.fn}` labels resolve the way the nav resolves them; one that
  resolves to nothing is dropped, as is a `readonly` badge or a `disabled`
  ("coming soon") link. None of them is a place you can go.
  """
  @spec flat_links(map(), map() | nil) :: [
          %{title: String.t(), href: String.t(), group: String.t() | nil}
        ]
  def flat_links(navigation, current_scope) when is_map(navigation) do
    auth_level = auth_level(Scope.user(current_scope))

    [
      {"primary_links", "any"},
      {"guest_links", "unauthenticated"},
      {"authenticated_links", "authenticated"},
      {"account_links", "authenticated"}
    ]
    |> Enum.flat_map(fn {key, default_auth} ->
      navigation
      |> section_entries(key, auth_level, default_auth, current_scope)
      |> Enum.flat_map(&flatten_entry(&1, nil))
    end)
  end

  def flat_links(_navigation, _current_scope), do: []

  defp flatten_entry(%{"items" => items} = entry, _group) when is_list(items) do
    group = label_presence(entry)

    Enum.flat_map(items, &flatten_entry(&1, group))
  end

  defp flatten_entry(entry, group) do
    href = Map.get(entry, "href")
    title = label_presence(entry)

    if inert?(entry) or is_nil(title) or not (is_binary(href) and href != "") do
      []
    else
      [%{title: title, href: href, group: group}]
    end
  end

  defp label_presence(entry) do
    case entry |> Map.get("label") |> translate_label() do
      label when is_binary(label) ->
        case String.trim(label) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp link_visible?(link, auth_level, default_auth) do
    required = required_auth(link, default_auth)

    case {required, auth_level} do
      {"any", _} -> true
      {"unauthenticated", :unauthenticated} -> true
      {"authenticated", :authenticated} -> true
      {"authenticated", :admin} -> true
      {"admin", :admin} -> true
      _ -> false
    end
  end

  defp required_auth(entry, default_auth) do
    auth = Map.get(entry, "auth") || Map.get(entry, :auth)

    cond do
      Map.get(entry, "admin_only") == true or Map.get(entry, :admin_only) == true -> "admin"
      is_binary(auth) -> auth
      is_atom(auth) and not is_nil(auth) -> Atom.to_string(auth)
      true -> default_auth
    end
  end

  defp auth_level(%{is_admin: true}), do: :admin
  defp auth_level(%{}), do: :authenticated
  defp auth_level(_), do: :unauthenticated

  defp any_entry_active?(entries, current_path) do
    Enum.any?(entries, &entry_active?(&1, current_path))
  end

  defp entry_active?(%{"items" => items}, current_path) when is_list(items) do
    Enum.any?(items, &entry_active?(&1, current_path))
  end

  defp entry_active?(entry, current_path), do: link_active?(entry, current_path)

  # Siblings in one menu can both match: `/docs` and `/docs/reference` each
  # start `/docs/reference/body2d`. Lighting both says the reader is in two
  # places, so among one list's links only the longest match is active. A
  # group is active when anything under it is, as before.
  defp sibling_active?(entry, current_path, best_href) do
    cond do
      dropdown_entry?(entry) -> entry_active?(entry, current_path)
      is_nil(best_href) -> link_active?(entry, current_path)
      true -> entry["href"] == best_href
    end
  end

  # The longest claim wins. On a tie the link with fewer `"active"` prefixes
  # wins: one that owns a section alone (Flashcards, `["/flashcards"]`) is its
  # own link, one that shares it among others (Dictionary, `["/vocabulary",
  # "/flashcards"]`) only stands in for it where the other is not drawn.
  defp best_href(entries, current_path) do
    entries
    |> Enum.reject(&dropdown_entry?/1)
    |> Enum.map(&{&1, match_length(&1, current_path)})
    |> Enum.reject(fn {_entry, length} -> is_nil(length) end)
    |> Enum.max_by(
      fn {entry, claim} -> {claim, -length(List.wrap(entry["active"]))} end,
      fn -> nil end
    )
    |> case do
      nil -> nil
      {entry, _length} -> entry["href"]
    end
  end

  defp dropdown_entry?(%{"items" => items}) when is_list(items), do: true
  defp dropdown_entry?(_entry), do: false

  defp link_active?(link, current_path), do: match_length(link, current_path) != nil

  # How much of the page's path the link claims: the longest of its href and
  # its `"active"` prefixes that the path starts with, or nil. `"active"` is
  # a list of clean paths a section owns besides its href (`["/vocabulary",
  # "/flashcards"]`): a link whose href names one page of the section
  # (`/vocabulary/spanish`) is still lit on the hub and the section's other
  # pages. `"match": "exact"` applies to the href alone.
  defp match_length(%{"href" => href} = link, current_path)
       when is_binary(href) and is_binary(current_path) do
    if external_href?(href) do
      nil
    else
      # Both sides get stripped: the href now carries the reader's locale
      # prefix, while `current_path` may be the clean path the PageMeta plug
      # stashed. Comparing them raw left the whole nav unhighlighted under /fr.
      known = GamendWeb.GettextSync.known_locales()
      href = GamendWeb.HostLayouts.strip_locale_prefix(href, known)
      current_path = GamendWeb.HostLayouts.strip_locale_prefix(current_path, known)

      href_match? =
        case Map.get(link, "match", "prefix") do
          "exact" -> current_path == href
          _ -> path_prefix?(current_path, href)
        end

      owned =
        link["active"]
        |> List.wrap()
        |> Enum.filter(&(is_binary(&1) and path_prefix?(current_path, &1)))

      if(href_match?, do: [href | owned], else: owned)
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> nil end)
    end
  end

  defp match_length(_link, _current_path), do: nil

  # Keeps the reader's locale prefix on the hand-written account links, the
  # same way `localize_hrefs/2` does for every configured nav entry.
  defp lp(href) do
    GamendWeb.HostLayouts.localized_href(href, GamendWeb.HostLayouts.current_locale())
  end

  # `current_path` carries the locale prefix on a prefixed page; these
  # hand-written active checks compare against clean paths.
  defp here?(current_path, prefix) when is_binary(current_path) do
    current_path
    |> GamendWeb.HostLayouts.strip_locale_prefix(GamendWeb.GettextSync.known_locales())
    |> path_prefix?(prefix)
  end

  defp here?(_current_path, _prefix), do: false

  # A prefix match stops at a path segment: `/game` covers `/game/web`, not
  # `/games`, a different page that shares the letters. A prefix ending in
  # `/` (`/`, `/docs/`) already marks the boundary.
  defp path_prefix?(path, prefix) do
    path == prefix or
      (String.ends_with?(prefix, "/") and String.starts_with?(path, prefix)) or
      String.starts_with?(path, prefix <> "/")
  end

  defp external_href?(href) do
    String.starts_with?(href, "http://") or String.starts_with?(href, "https://")
  end

  defp locale_links(current_path, current_query, known_locales) do
    locale_labels = GamendWeb.HostLayouts.locale_labels()
    base_path = GamendWeb.HostLayouts.strip_locale_prefix(current_path || "/", known_locales)

    query_suffix =
      if is_binary(current_query) and current_query != "", do: "?" <> current_query, else: ""

    # A locale prefix is only served as a real page for the paths in
    # `:localized_paths`; everywhere else it redirects to the clean URL. The
    # switcher still needs those links — following one is how a reader changes
    # language — but a crawler following 30 of them per page just generates
    # redirects. On this site that was 278 URLs reported as "Page with
    # redirect", i.e. most of the crawl budget spent on nothing.
    crawlable? = LocalePath.localized_path?(base_path)
    default_locale = LocalePath.default_locale()
    flags? = locale_flags?()

    Enum.map(known_locales, fn locale ->
      # BCP-47 in the URL (`/pt-BR`), not the gettext form (`/pt_BR`): that is
      # what `hreflang` advertises and what the router declares, so emitting
      # the underscore here pointed at routes that do not exist.
      prefix = "/" <> LocalePath.url_locale(locale)

      # The default locale is never served under a prefix — `/en/about`
      # redirects to `/about` — so linking it prefixed publishes a followable
      # link that can only ever redirect. On a localized path `nofollow` does
      # not apply, so every page shipped one of these: 229 URLs reported as
      # "Page with redirect". Point at the clean URL the sitemap and the
      # `hreflang` alternates already use.
      #
      # The clean URL alone is not enough to *switch* to it: the reader's
      # session still holds the language they are leaving, and `LocalePath`
      # redirects them back to it. `?setlang=` is what says otherwise. It is the
      # one switcher link a crawler must not follow — it can only redirect —
      # but nothing is lost by that: `hreflang="en"` and `x-default` in the head
      # already point at the same clean URL.
      href =
        cond do
          locale == default_locale ->
            if(base_path == "/", do: "/", else: base_path) <> switch_suffix(query_suffix, locale)

          base_path == "/" ->
            prefix <> query_suffix

          true ->
            prefix <> base_path <> query_suffix
        end

      %{
        locale: locale,
        label: Map.get(locale_labels, locale, locale),
        href: href,
        rel: unless(crawlable? and locale != default_locale, do: "nofollow"),
        flag_code: locale_flag(locale, flags?)
      }
    end)
  end

  defp switch_suffix("", locale), do: "?" <> LocalePath.switch_param() <> "=" <> locale

  defp switch_suffix(query, locale),
    do: query <> "&" <> LocalePath.switch_param() <> "=" <> locale

  defp locale_label(locale) do
    locale
    |> then(&Map.get(GamendWeb.HostLayouts.locale_labels(), &1, &1))
  end

  attr :flag_code, :string, default: nil
  attr :label, :string, default: nil, doc: "for a screen reader, where the mark stands alone"

  # The switcher's button mark: the current language's flag, or a language
  # icon when flags are switched off (`GamendWeb.Features`, `locale_flags`).
  defp locale_mark(%{flag_code: nil} = assigns) do
    ~H"""
    <.icon name="hero-language" class="size-5" />
    <span :if={@label} class="sr-only">{@label}</span>
    """
  end

  defp locale_mark(assigns) do
    ~H"""
    <.flag code={@flag_code} priority class="rounded-[2px] ring-1 ring-base-content/10" />
    <span :if={@label} class="sr-only">{@label}</span>
    """
  end

  defp locale_flags?, do: GamendWeb.Features.enabled?(:locale_flags)

  # The flag drawn for `locale`, or nil when the host switched flags off.
  defp locale_flag(_locale, false), do: nil
  defp locale_flag(locale, true), do: locale_flag_code(locale)

  defp locale_flag_code("ar"), do: "sa"
  defp locale_flag_code("bg"), do: "bg"
  defp locale_flag_code("cs"), do: "cz"
  defp locale_flag_code("da"), do: "dk"
  defp locale_flag_code("de"), do: "de"
  defp locale_flag_code("el"), do: "gr"
  defp locale_flag_code("en"), do: "gb"
  defp locale_flag_code("es"), do: "es"
  defp locale_flag_code("fi"), do: "fi"
  defp locale_flag_code("fr"), do: "fr"
  defp locale_flag_code("hu"), do: "hu"
  defp locale_flag_code("id"), do: "id"
  defp locale_flag_code("it"), do: "it"
  defp locale_flag_code("ja"), do: "jp"
  defp locale_flag_code("ko"), do: "kr"
  defp locale_flag_code("nl"), do: "nl"
  defp locale_flag_code("no"), do: "no"
  defp locale_flag_code("pl"), do: "pl"
  defp locale_flag_code("pt"), do: "pt"
  defp locale_flag_code("pt_BR"), do: "br"
  defp locale_flag_code("ro"), do: "ro"
  defp locale_flag_code("ru"), do: "ru"
  defp locale_flag_code("sv"), do: "se"
  defp locale_flag_code("th"), do: "th"
  defp locale_flag_code("tr"), do: "tr"
  defp locale_flag_code("uk"), do: "ua"
  defp locale_flag_code("vi"), do: "vn"
  defp locale_flag_code("zh_CN"), do: "cn"
  defp locale_flag_code("zh_TW"), do: "tw"
  defp locale_flag_code(_locale), do: "xx"

  defp display_name(user) do
    cond do
      is_binary(user.display_name) and user.display_name != "" -> user.display_name
      is_binary(user.email) and user.email != "" -> user.email
      true -> "User"
    end
  end

  defp translate_label(label) when is_binary(label) do
    GamendWeb.HostLayouts.translate(label)
  end

  defp translate_label(label), do: label

  # Base icon size plus an optional per-item color class from config.
  # An entry's `"color"` is a class on its icon; its `"tone"` colours the
  # icon from the host's `--nav-tone` (`tone/1`).
  defp icon_class(entry, size \\ "w-4 h-4") do
    [size, entry["color"], tone(entry) && "text-(--nav-tone)"]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" ")
  end

  # An entry's `"tone"`: a name the host colours. Every nav link carries it as
  # `data-tone`, and the host's stylesheet gives `[data-tone=<name>]` its
  # `--nav-tone` (one per theme); core knows no colours. The icon takes the
  # tone, and the page's own link a tint of it (`state_class/3`) where an
  # untoned one is filled with the primary.
  defp tone(entry) do
    case entry["tone"] do
      tone when is_binary(tone) and tone != "" -> tone
      _ -> nil
    end
  end

  # `oklab`, not `oklch`: the light theme's base is a grey at hue 0, and an
  # `oklch` mix turns the tone's hue towards it (a blue tint came out pink).
  @tone_active "bg-[color-mix(in_oklab,var(--nav-tone)_16%,var(--color-base-100))] border-[color-mix(in_oklab,var(--nav-tone)_45%,transparent)]"

  # The same edge drawn inside, for a tab of the tab bar (`side_nav_item/1`).
  @tone_ring "ring-1 ring-[color-mix(in_oklab,var(--nav-tone)_45%,transparent)]"

  # A link button's colour: the page's own (`active?`) filled with the
  # primary, or tinted with its tone; any other `inactive`.
  defp state_class(entry, true, _inactive) do
    if tone(entry), do: ["btn-ghost", @tone_active], else: "btn-primary"
  end

  defp state_class(_entry, false, inactive), do: inactive

  defp tone_active, do: @tone_active
  defp tone_ring, do: @tone_ring

  attr :current_path, :string, default: nil

  # The bar's Log in and Register (`desktop_nav/1`). Their words stay at every
  # stage `navbar_fit.js` steps through: an icon alone reads as neither, and
  # the bar gives way to the menu before it would drop them. One is
  # `btn-primary` (2026-10-23, user): the page the reader is on, else
  # Register, the one a new reader should press. With `web_registration` off
  # the game registers its players: Log in stands alone, and is the one.
  defp auth_buttons(assigns) do
    register? = GamendWeb.Features.enabled?(:web_registration)

    primary =
      if register? and not here?(assigns.current_path, ~p"/users/log_in"),
        do: ~p"/users/register",
        else: ~p"/users/log_in"

    assigns = assign(assigns, entries: auth_entries(register?), primary: primary)

    ~H"""
    <li :for={{path, icon, label} <- @entries}>
      <.link
        href={lp(path)}
        class={["btn gap-1", if(path == @primary, do: "btn-primary", else: "btn-surface")]}
      >
        <.icon name={icon} class="w-4 h-4" />
        <span>{GamendWeb.HostLayouts.translate(label)}</span>
      </.link>
    </li>
    """
  end

  defp auth_entries(register?) do
    log_in = {~p"/users/log_in", "hero-arrow-right-on-rectangle-solid", "Log in"}
    register = {~p"/users/register", "hero-user-plus-solid", "Register"}

    if register?, do: [log_in, register], else: [log_in]
  end

  attr :class, :any, default: nil

  defp nav_divider(assigns) do
    ~H"""
    <li class={["flex items-center px-0", @class]}>
      <div class="w-px h-6 bg-base-content/20"></div>
    </li>
    """
  end
end
