defmodule GamendWeb.PresentationPage do
  @moduledoc """
  Shared hero-and-sections page renderer for host presentation pages.
  """

  use GamendWeb, :html

  require Logger

  alias GamendWeb.ProjectStatic
  alias Phoenix.HTML.Safe

  @bold_pattern ~r/\*\*(.+?)\*\*/
  @italic_pattern ~r/(?<!\*)\*([^*\n]+)\*(?!\*)/
  @link_pattern ~r/\[([^\]]+)\]\(([^)\s]+)\)/

  def page_for_path(theme, path) when is_map(theme) do
    normalized_path = normalize_path(path)

    theme
    |> Map.get("pages", %{})
    |> case do
      pages when is_map(pages) ->
        Enum.find_value(pages, fn {key, page} ->
          if presentation_page?(page) and normalize_path(Map.get(page, "path")) == normalized_path do
            Map.put(page, "key", key)
          end
        end)

      _ ->
        nil
    end
  end

  def page_for_path(_theme, _path), do: nil

  def page_title(page, fallback \\ "Page")

  def page_title(page, fallback) when is_map(page) do
    case get_in(page, ["hero", "title"]) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback
    end
  end

  def page_title(_page, fallback), do: fallback

  @doc """
  `page/1` rendered to HTML, memoised per `{locale, path}`.

  The body of a presentation page is the largest single cost in the response
  and none of it depends on the reader: `page/1` reads only `hero`, `sections`
  and `background_icons`, all derived from the theme config and the locale, and
  the module references no conn, scope, user, gettext call, clock or random
  source. Two anonymous visitors, or one visitor and the same visitor an hour
  later, were being served bytes that had been built from scratch each time --
  0.64 ms of a 1.9 ms home page, 57 KB of a 102 KB document.

  The value carries a fingerprint of the inputs, so an edited theme cannot
  serve a stale body: a changed `page` map hashes differently and re-renders.
  The fingerprint lives in the value rather than the key so the key set stays
  bounded -- a theme edit overwrites its entry instead of stranding the old
  one. It is a fingerprint rather than the inputs themselves because a cache
  read that hands back the page map costs more than the render it replaces:
  measured at 0.66 ms against 0.47 ms to just render the thing.

  A fingerprint is also why this does not key on a theme version.
  `resolve_theme/2` merges `conn.assigns[:theme]`, so a host that varies the
  theme per request would be served another request's page by a version-keyed
  cache. Hashing the actual inputs cannot make that mistake.

  `:persistent_term`, like the icon and theme caches beside it, and not the
  application cache: `Gamend.Cache` is multilevel and would put a Redis round
  trip in the render path, and reaching past it into `Gamend.Cache.L1` makes
  every page on the site depend on another app's cache process being started
  -- which in the web app's own test env it is not, so the site did not render
  at all. `:persistent_term` has no owner and cannot be missing.

  Its one cost is that every write scans every process on the node, so this is
  only safe because the key set is bounded by configuration rather than by
  traffic: `cached_body/4` is reached only for a path the theme actually
  configures (an unknown path is a 404 before this point), so the entries are
  configured pages times locales, each written once per theme version.
  """
  @spec cached_body(map(), list(), String.t() | nil, String.t()) :: iodata()
  def cached_body(page_map, background_icons, locale, path) do
    # The static generation is an input too: the srcsets list only the width
    # variants on disk, and those can be cut after boot (see
    # `GamendWeb.ResponsiveImages`) without the page map changing at all.
    fingerprint =
      :erlang.phash2({page_map, background_icons, ProjectStatic.generation()})

    key = {__MODULE__, :body, locale, path}

    case :persistent_term.get(key, :miss) do
      {^fingerprint, html} ->
        html

      _ ->
        html =
          %{
            __changed__: nil,
            page: page_map,
            background_icons: background_icons,
            full_bleed_hero: true
          }
          |> page()
          |> Safe.to_iodata()
          |> IO.iodata_to_binary()

        :persistent_term.put(key, {fingerprint, html})
        html
    end
  end

  attr :page, :map, required: true
  attr :background_icons, :list, default: []
  attr :full_bleed_hero, :boolean, default: true

  def page(assigns) do
    sections = sections_with_page_defaults(assigns.page)

    assigns =
      assign(assigns,
        hero: Map.get(assigns.page, "hero", %{}),
        sections: sections,
        sections_columns: sections_columns(assigns.page),
        background_icon_bands: background_icon_bands(sections)
      )

    ~H"""
    <%!-- Full bleed by negative inline margin, not `left-1/2 -translate-x-1/2`:
          the offset half of that pair is physical while the translate is not,
          so under `dir="rtl"` the two stopped cancelling and the hero sat 128px
          off the viewport — the Arabic home page had its title clipped at one
          edge and a blank strip at the other. `margin-inline` is symmetrical
          and needs no positioning at all. --%>
    <div class={if(@full_bleed_hero, do: "relative w-screen mx-[calc(50%-50vw)] -mt-20", else: "")}>
      <div class="relative overflow-hidden">
        <.background_icons icons={@background_icons} bands={@background_icon_bands} />
        <%!-- `hero.media_layout: "cover"` turns the hero into a banner: the
              image fills it edge to edge behind a scrim with the title over
              the top. Without it the hero keeps media in its own column. --%>
        <.hero_cover :if={hero_cover?(@hero)} hero={@hero} sections={@sections} />
        <section :if={!hero_cover?(@hero)} class="relative min-h-dvh">
          <div class="relative z-10 flex min-h-dvh items-center px-6 pb-12 pt-24 sm:px-8 lg:px-12">
            <div class={[
              "mx-auto grid w-full items-center gap-8 lg:gap-12",
              content_width_class(),
              grid_class(@hero, "hero")
            ]}>
              <div class={media_order_class(@hero)}>
                <.media item={@hero} variant="hero" />
              </div>
              <div class={[
                "flex flex-col gap-5",
                text_order_class(@hero),
                text_align_class(@hero)
              ]}>
                <h1 class="text-4xl font-extrabold tracking-normal sm:text-5xl lg:text-6xl">
                  {Map.get(@hero, "title", "")}
                </h1>
                <div class="max-w-2xl text-base leading-relaxed text-muted sm:text-lg lg:text-xl">
                  {rich_text(Map.get(@hero, "text", ""))}
                </div>
                <.buttons buttons={Map.get(@hero, "buttons", [])} />
              </div>
            </div>
          </div>
          <a
            :if={@sections != []}
            href="#more-content"
            aria-label={gettext("Scroll to content")}
            class="absolute bottom-6 left-1/2 z-20 -translate-x-1/2 text-muted transition hover:text-base-content motion-safe:animate-bounce"
          >
            <.dynamic_icon name="hero-chevron-down-solid" class="size-9" />
          </a>
        </section>

        <div id="more-content" class="scroll-mt-20"></div>

        <div
          :if={@sections != []}
          class={[
            "relative z-10 mx-auto grid w-full gap-y-4 px-4 sm:px-6 lg:px-8",
            sections_columns_class(@sections_columns),
            content_width_class()
          ]}
        >
          <%= for section <- @sections do %>
            <.section section={section} columns={@sections_columns} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp has_copy?(item) do
    not is_nil(non_empty_string(Map.get(item, "title"))) or
      not is_nil(non_empty_string(Map.get(item, "text"))) or
      has_buttons?(item)
  end

  # A hero opts into the banner treatment with `"media_layout": "cover"` and an
  # image; anything else keeps the two-column hero.
  defp hero_cover?(hero) do
    Map.get(hero, "media_layout") == "cover" and image_config(hero).light != nil
  end

  attr :hero, :map, required: true
  attr :sections, :list, default: []

  defp hero_cover(assigns) do
    ~H"""
    <%!-- Exactly one screen, never more. The wrapper's -mt-20 cancels the
          layout's top offset rather than pulling the hero above the fold, so
          the hero starts at y=0 and any extra height is pure overflow.
          `dvh` (not `vh`) tracks mobile browser chrome, so the banner keeps
          filling the visible area instead of hiding behind the URL bar. --%>
    <.cover_banner item={@hero} heading="h1" class="min-h-[100dvh]">
      <a
        :if={@sections != []}
        href="#more-content"
        aria-label={gettext("Scroll to content")}
        class="absolute bottom-6 left-1/2 z-20 -translate-x-1/2 text-white/70 transition hover:text-white motion-safe:animate-bounce"
      >
        <.dynamic_icon name="hero-chevron-down-solid" class="size-9" />
      </a>
    </.cover_banner>
    """
  end

  attr :item, :map, required: true
  attr :heading, :string, default: "h2"
  attr :class, :string, default: nil
  attr :eager, :boolean, default: true
  slot :inner_block

  @doc false
  # The shared banner treatment: the image fills the block and the title, text
  # and buttons sit on top of it. Used by a `media_layout: "cover"` hero and by
  # `media_layout: "bleed"` sections, so the two read as one design.
  def cover_banner(assigns) do
    assigns =
      assign(assigns,
        image: image_config(assigns.item),
        fit: media_fit_class(assigns.item),
        loading: if(assigns.eager, do: "eager", else: "lazy"),
        # non_empty_string/1 returns the string (or nil), not a boolean.
        has_copy: has_copy?(assigns.item),
        scrim: has_copy?(assigns.item) and Map.get(assigns.item, "scrim") != false
      )

    ~H"""
    <section class={[
      "relative z-[2] flex items-center justify-center overflow-hidden",
      @class
    ]}>
      <%!-- Portrait art (when supplied) below `sm`, landscape above it.
            Breakpoint lives on the wrapper and theme on the images: putting
            both on one element loses to attribute-selector specificity. --%>
      <div :if={@image.portrait} class="absolute inset-0 sm:hidden">
        <img
          src={@image.portrait}
          alt={@image.alt}
          loading={@loading}
          decoding="async"
          class={[
            "h-full w-full",
            @fit,
            @image.portrait_dark && "[[data-theme=dark]_&]:hidden"
          ]}
        />
        <img
          :if={@image.portrait_dark}
          src={@image.portrait_dark}
          alt={@image.alt}
          loading={@loading}
          decoding="async"
          class={["hidden h-full w-full [[data-theme=dark]_&]:block", @fit]}
        />
      </div>
      <div class={["absolute inset-0", @image.portrait && "hidden sm:block"]}>
        <img
          src={@image.light}
          alt={@image.alt}
          width={@image.width}
          height={@image.height}
          loading={@loading}
          decoding="async"
          class={["h-full w-full", @fit, @image.dark && "[[data-theme=dark]_&]:hidden"]}
        />
        <img
          :if={@image.dark}
          src={@image.dark}
          alt={@image.alt}
          width={@image.width}
          height={@image.height}
          loading={@loading}
          decoding="async"
          class={["hidden h-full w-full [[data-theme=dark]_&]:block", @fit]}
        />
      </div>
      <%!-- Scrim and copy only when there is something to overlay. A banner
            with no title is just the picture: dimming it would cost contrast
            for nothing. --%>
      <%= if @has_copy do %>
        <%!-- Theme-aware: a light-theme capture is bright and needs a real
              wash for white text to read, while the dark-theme capture is
              already dark and the same wash would flatten it to black. --%>
        <div :if={@scrim} class="absolute inset-0 bg-black/45 [[data-theme=dark]_&]:bg-black/20">
        </div>
        <div
          :if={@scrim}
          class="absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-black/40 [[data-theme=dark]_&]:from-black/60 [[data-theme=dark]_&]:to-black/25"
        >
        </div>
        <div class="relative z-10 flex w-full flex-col items-center gap-5 px-6 py-12 text-center">
          <h1
            :if={@heading == "h1"}
            class="text-4xl font-extrabold tracking-normal text-white [text-shadow:0_2px_6px_rgb(0_0_0_/_0.95),0_4px_24px_rgb(0_0_0_/_0.8)] sm:text-5xl lg:text-6xl"
          >
            {Map.get(@item, "title", "")}
          </h1>
          <h2
            :if={@heading != "h1"}
            class="text-2xl font-bold tracking-normal text-white [text-shadow:0_2px_6px_rgb(0_0_0_/_0.95),0_4px_24px_rgb(0_0_0_/_0.8)] sm:text-3xl"
          >
            {Map.get(@item, "title", "")}
          </h2>
          <div
            :if={non_empty_string(Map.get(@item, "text"))}
            class="max-w-2xl text-base leading-relaxed text-white/90 [text-shadow:0_1px_8px_rgb(0_0_0_/_0.8)] sm:text-lg"
          >
            {rich_text(Map.get(@item, "text", ""))}
          </div>
          <.buttons :if={has_buttons?(@item)} buttons={Map.get(@item, "buttons", [])} />
        </div>
      <% end %>
      {render_slot(@inner_block)}
    </section>
    """
  end

  # `"media_fit": "contain"` shows the WHOLE image (letterboxed against the
  # section background); the default "cover" fills the section and crops.
  defp media_fit_class(item) do
    case Map.get(item, "media_fit") do
      "contain" -> "object-contain"
      _ -> "object-cover"
    end
  end

  attr :icons, :list, default: []
  attr :bands, :integer, default: 1

  def background_icons(assigns) do
    icons = if is_list(assigns.icons), do: assigns.icons, else: []
    bands = max(assigns.bands, 1)

    assigns =
      assign(assigns,
        placements: GamendWeb.Layouts.icon_placements(icons),
        bands: Enum.to_list(0..(bands - 1))
      )

    ~H"""
    <div
      :if={@placements != []}
      class="absolute inset-0 overflow-hidden pointer-events-none z-[1]"
      aria-hidden="true"
    >
      <%= for band <- @bands do %>
        <div
          class="absolute left-0 top-0 h-dvh w-full"
          style={"transform: translateY(#{band * 100}dvh);"}
        >
          <%= for placement <- @placements do %>
            <div
              class={[
                "absolute text-base-content [[data-theme=dark]_&]:text-white opacity-[0.08] [[data-theme=dark]_&]:opacity-[0.10]",
                placement.size
              ]}
              style={"top: #{placement.top}%; #{placement_side_style(placement)}; animation: float #{placement.dur}s ease-in-out infinite #{background_icon_delay(placement, band)}s;"}
            >
              <.dynamic_icon name={placement.name} class={placement.size} />
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :buttons, :list, default: []

  @doc """
  A row of call-to-action buttons from config.

  Per button: `label`, `href`, optional `icon`, `style` and `external`, plus
  `badge` (a short tag after the label, translated like the label: "Pro",
  "Coming soon") and `disabled` (drawn as the button but not a link, for
  something announced and not yet there; `href` may then be left out).
  """
  def buttons(assigns) do
    buttons = if is_list(assigns.buttons), do: assigns.buttons, else: []
    assigns = assign(assigns, buttons: Enum.filter(buttons, &valid_button?/1))

    ~H"""
    <div
      :if={@buttons != []}
      class="flex w-full flex-col items-center justify-center gap-3 sm:flex-row sm:flex-wrap"
    >
      <%= for button <- @buttons do %>
        <span
          :if={button["disabled"] == true}
          aria-disabled="true"
          class={[button_class(button), "cursor-default opacity-70 hover:scale-100"]}
        >
          <.button_content button={button} />
        </span>
        <a
          :if={button["disabled"] != true}
          href={button["href"]}
          target={if button["external"], do: "_blank"}
          rel={if button["external"], do: "noopener noreferrer"}
          class={button_class(button)}
        >
          <.button_content button={button} />
        </a>
      <% end %>
    </div>
    """
  end

  attr :button, :map, required: true

  defp button_content(assigns) do
    ~H"""
    <.dynamic_icon
      :if={@button["icon"]}
      name={@button["icon"]}
      class="size-5 shrink-0 text-current"
    />
    <span class="truncate">{Map.get(@button, "label", "")}</span>
    <span
      :if={non_empty_string(@button["badge"])}
      class={["badge badge-sm shrink-0 whitespace-nowrap", badge_class(@button)]}
    >
      {@button["badge"]}
    </span>
    """
  end

  attr :links, :list, default: []
  attr :align, :string, default: "start"

  @doc """
  A section's `"links"`: a wrapping row of small link chips.

  Buttons are calls to action and stay few; this is for a section whose point
  is the *list* — a directory of a dozen destinations, like the home page's
  language index. `label` and `href` per entry, nothing else: no icons, no
  styles, so a long row stays a quiet block of navigation rather than twenty
  competing buttons. Hrefs are theme config like button hrefs, and are locale-
  prefixed by the same `localize_hrefs` pass in the page controller.
  """
  def link_chips(assigns) do
    links = if is_list(assigns.links), do: assigns.links, else: []

    assigns =
      assign(assigns,
        links:
          Enum.filter(links, &(non_empty_string(&1["label"]) && non_empty_string(&1["href"])))
      )

    ~H"""
    <ul
      :if={@links != []}
      class={[
        "flex flex-wrap gap-2",
        if(@align == "center", do: "justify-center")
      ]}
    >
      <li :for={link <- @links}>
        <a
          href={link["href"]}
          class="block rounded-lg border border-base-300 px-3 py-1.5 text-sm font-bold transition hover:border-primary/40 hover:bg-base-200"
        >
          {link["label"]}
        </a>
      </li>
    </ul>
    """
  end

  defp has_links?(item) when is_map(item) do
    case Map.get(item, "links") do
      links when is_list(links) -> links != []
      _ -> false
    end
  end

  defp has_links?(_item), do: false

  attr :cards, :list, default: []

  @doc """
  A section's `"cards"`: a grid of small cards, each an icon, a title and a
  line of text, optionally a link.

  For the section whose point is a *set* — twelve features, five personas,
  the four things a product does — where a paragraph would list them and a
  reader would skim past. Three across from `lg`, two from `sm`, one below.
  `icon` is a heroicon name; `href` makes the whole card the link.
  """
  def card_grid(assigns) do
    cards = if is_list(assigns.cards), do: assigns.cards, else: []

    assigns = assign(assigns, cards: Enum.filter(cards, &non_empty_string(&1["title"])))

    ~H"""
    <ul :if={@cards != []} class="grid w-full gap-4 text-start sm:grid-cols-2 lg:grid-cols-3">
      <li :for={card <- @cards} class="h-full">
        <.card_body card={card} />
      </li>
    </ul>
    """
  end

  attr :card, :map, required: true

  # One card, a link when it has somewhere to go. The two markups differ only
  # in the outer element, so the inner block is written once below.
  defp card_body(%{card: %{"href" => href}} = assigns) when is_binary(href) and href != "" do
    ~H"""
    <a
      href={@card["href"]}
      class="flex h-full flex-col gap-2 rounded-xl border border-base-300 bg-base-100/80 p-4 transition hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md"
    >
      <.card_inner card={@card} />
    </a>
    """
  end

  defp card_body(assigns) do
    ~H"""
    <div class="flex h-full flex-col gap-2 rounded-xl border border-base-300 bg-base-100/80 p-4">
      <.card_inner card={@card} />
    </div>
    """
  end

  attr :card, :map, required: true

  defp card_inner(assigns) do
    ~H"""
    <span :if={non_empty_string(@card["icon"])} class="text-primary">
      <.icon name={@card["icon"]} class="size-6" />
    </span>
    <span class="font-bold">{@card["title"]}</span>
    <span :if={non_empty_string(@card["text"])} class="text-sm leading-relaxed text-muted">
      {rich_text(@card["text"])}
    </span>
    """
  end

  defp has_cards?(item) when is_map(item) do
    case Map.get(item, "cards") do
      cards when is_list(cards) -> cards != []
      _ -> false
    end
  end

  defp has_cards?(_item), do: false

  attr :section, :map, required: true

  @doc """
  A section's `"component"`: a block the host draws itself, by name.

  The name resolves through `config :gamend_web, :presentation_components,
  %{"languages" => {MyHost.HomeLanguages, :strip}}` to a function component,
  called with `%{section: section}` and drawn between the section's text and
  its links. For the block a config page cannot describe — a strip of every
  language with its flag, a live count — while the page around it stays
  config.

  It renders inside `cached_body/4`'s memo, so it must depend on the config
  and the locale only: a gettext call is fine (the memo is per locale), a
  reader, a clock or a random source is not. A name the config does not map
  draws nothing and is logged, so a typo shows in the logs rather than as a
  blank nobody reports.
  """
  def host_component(assigns) do
    case component_for(assigns.section) do
      {module, function} ->
        apply(module, function, [%{__changed__: nil, section: assigns.section}])

      nil ->
        ~H""
    end
  end

  defp component_for(section) do
    name = non_empty_string(Map.get(section, "component"))
    components = Application.get_env(:gamend_web, :presentation_components, %{})

    case name && Map.get(components, name) do
      {module, function} when is_atom(module) and is_atom(function) ->
        {module, function}

      _ ->
        if name do
          Logger.warning(
            "presentation section names a component the host does not register: #{inspect(name)}"
          )
        end

        nil
    end
  end

  defp has_component?(item) when is_map(item),
    do: non_empty_string(Map.get(item, "component")) != nil

  defp has_component?(_item), do: false

  attr :entries, :list, required: true, doc: "`%{question: _, answer: _}` maps"
  attr :class, :any, default: nil, doc: "layout only"

  @doc """
  Questions and their answers, every answer shown: a closed disclosure hides
  the text a reader scanned the page for. An answer takes the same light
  markup as a section's text (`rich_text/1`).

  A section's `"faq": [{"question": …, "answer": …}]` renders one, and
  `faq_entries/1` reads them back for a host's `FAQPage` markup, so the
  page and its structured data cannot disagree.
  """
  def faq(assigns) do
    ~H"""
    <dl class={["space-y-4 text-start", @class]}>
      <div :for={entry <- @entries}>
        <dt class="font-bold">{entry.question}</dt>
        <dd class="text-muted">{rich_text(entry.answer)}</dd>
      </div>
    </dl>
    """
  end

  @doc "The questions a page's sections carry, in page order."
  @spec faq_entries(map() | nil) :: [%{question: String.t(), answer: String.t()}]
  def faq_entries(page) when is_map(page) do
    page
    |> Map.get("sections")
    |> List.wrap()
    |> Enum.flat_map(&section_faq/1)
  end

  def faq_entries(_page), do: []

  defp section_faq(%{"faq" => entries}) when is_list(entries) do
    for %{"question" => question, "answer" => answer} <- entries,
        is_binary(question) and question != "",
        is_binary(answer) and answer != "",
        do: %{question: question, answer: answer}
  end

  defp section_faq(_section), do: []

  @doc """
  `rich_text/1`'s input with its markup taken out: a link keeps its label,
  bold and italic their words. For text that leaves the page, such as
  structured data.
  """
  @spec plain_text(String.t()) :: String.t()
  def plain_text(text) when is_binary(text) do
    text
    |> then(&Regex.replace(@link_pattern, &1, "\\1"))
    |> then(&Regex.replace(@bold_pattern, &1, "\\1"))
    |> then(&Regex.replace(@italic_pattern, &1, "\\1"))
  end

  attr :item, :map, required: true
  attr :variant, :string, default: "section"
  attr :columns, :integer, default: 1

  @doc """
  A section's illustration: video, image, light/dark image pair, or icon.

  Images carry `data-lightbox`, which a host may pick up to open them
  full-size. Inert on its own, so a host that ships no such script renders
  exactly what it did before. The `cover` layout's images are backgrounds
  rather than illustrations and are deliberately not marked.
  """
  def media(assigns) do
    image = image_config(assigns.item)
    sizes = image.sizes || media_sizes(assigns.item, assigns.variant, assigns.columns)
    image = %{image | sizes: sizes}

    assigns =
      assign(assigns,
        image: image,
        video: video_config(assigns.item),
        icon: Map.get(assigns.item, "icon"),
        size: media_size(assigns.item, assigns.variant)
      )

    ~H"""
    <div class="flex w-full items-center justify-center">
      <div class={media_shell_class()}>
        <.media_visual
          image={@image}
          video={@video}
          icon={@icon}
          variant={@variant}
          size={@size}
        />
      </div>
    </div>
    """
  end

  attr :image, :map, default: %{}
  attr :video, :map, default: %{}
  attr :icon, :string, default: nil
  attr :variant, :string, default: "section"
  attr :size, :string, default: "section"

  def media_visual(assigns) do
    # `media_visual/1` is public and callable with a partial `image` or no
    # `video` at all, both of which default to a bare `%{}` — merge over the
    # full shape so the template can read `@video.src` and `@image.light_srcset`
    # unconditionally.
    assigns =
      assigns
      |> assign(:video, Map.merge(empty_video_config(), assigns.video))
      |> assign(:image, Map.merge(empty_image_config(), assigns.image))

    ~H"""
    <%!-- `controls` is added on the first click, not rendered here — see
          assets/js/video_click_to_play.js. Every browser paints its own dark
          chrome over an unplayed video (Chrome a black gradient along the
          bottom, Safari a dim over the whole frame), so the poster a visitor
          actually sees is far darker than the video it advertises, and no
          choice of poster frame can change that.

          The overlay is a real <button>: without `controls` the video is not
          focusable or operable by keyboard, and the poster alone gives no hint
          that it is playable. --%>
    <div :if={@video.src} class="relative w-full" data-video-cta>
      <video
        src={@video.src}
        poster={@video.poster}
        width={@video.width}
        height={@video.height}
        aria-label={@video.alt}
        preload={@video.preload}
        muted={@video.muted}
        playsinline
        class={media_video_class(@size)}
      ></video>
      <button
        type="button"
        data-video-cta-play
        aria-label={gettext("Play video")}
        class={[
          "group absolute inset-0 grid cursor-pointer place-items-center rounded-lg",
          "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        ]}
      >
        <span class="grid size-16 place-items-center rounded-full bg-base-100/85 text-base-content shadow-lg ring-1 ring-base-content/10 backdrop-blur-sm transition group-hover:scale-105 group-hover:bg-base-100">
          <.icon name="hero-play-solid" class="size-7" />
        </span>
      </button>
    </div>
    <img
      :if={!@video.src && @image.light && !@image.dark}
      src={@image.light}
      srcset={@image.light_srcset}
      sizes={@image.light_srcset && (@image.sizes || media_sizes(%{}, @variant, 1))}
      alt={@image.alt}
      width={@image.width}
      height={@image.height}
      loading={if(@variant == "hero", do: "eager", else: "lazy")}
      fetchpriority={if(@variant == "hero", do: "high", else: nil)}
      decoding="async"
      data-lightbox
      class={media_class(@size, @image)}
    />
    <div :if={!@video.src && @image.light && @image.dark} class="contents">
      <img
        src={@image.light}
        srcset={@image.light_srcset}
        sizes={@image.light_srcset && (@image.sizes || media_sizes(%{}, @variant, 1))}
        alt={@image.alt}
        width={@image.width}
        height={@image.height}
        loading={if(@variant == "hero", do: "eager", else: "lazy")}
        fetchpriority={if(@variant == "hero", do: "high", else: nil)}
        decoding="async"
        data-lightbox
        class={[media_class(@size, @image), "[[data-theme=dark]_&]:hidden"]}
      />
      <img
        src={@image.dark}
        srcset={@image.dark_srcset}
        sizes={@image.dark_srcset && (@image.sizes || media_sizes(%{}, @variant, 1))}
        alt={@image.alt}
        width={@image.width}
        height={@image.height}
        loading={if(@variant == "hero", do: "eager", else: "lazy")}
        fetchpriority={if(@variant == "hero", do: "high", else: nil)}
        decoding="async"
        data-lightbox
        class={[media_class(@size, @image), "hidden [[data-theme=dark]_&]:block"]}
      />
    </div>
    <div
      :if={!@video.src && !@image.light && @icon}
      class="grid aspect-square w-full max-w-48 place-items-center rounded-lg bg-base-100/70 text-muted shadow-sm"
    >
      <.dynamic_icon name={@icon} class="size-16" />
    </div>
    """
  end

  attr :section, :map, required: true
  attr :columns, :integer, default: 1

  # `"media_layout": "cover"` uses the image as the section's cover: it fills
  # the whole section (object-cover behind a scrim) with the title, text and
  # buttons overlaid in the center. Pair with `"height": "full"` for a
  # one-per-viewport banner.
  def section(%{section: %{"media_layout" => "cover"}} = assigns) do
    assigns = assign(assigns, image: image_config(assigns.section))

    ~H"""
    <section class={[
      "relative flex w-full items-center justify-center overflow-hidden rounded-lg",
      section_height_class(@section)
    ]}>
      <img
        :if={@image.light}
        src={@image.light}
        srcset={@image.light_srcset}
        sizes={@image.light_srcset && "100vw"}
        alt={@image.alt}
        width={@image.width}
        height={@image.height}
        loading="lazy"
        decoding="async"
        class={[
          "absolute inset-0 h-full w-full object-cover",
          @image.dark && "[[data-theme=dark]_&]:hidden"
        ]}
      />
      <img
        :if={@image.dark}
        src={@image.dark}
        srcset={@image.dark_srcset}
        sizes={@image.dark_srcset && "100vw"}
        alt={@image.alt}
        width={@image.width}
        height={@image.height}
        loading="lazy"
        decoding="async"
        class="absolute inset-0 hidden h-full w-full object-cover [[data-theme=dark]_&]:block"
      />
      <div class="absolute inset-0 bg-gradient-to-t from-black/70 via-black/30 to-black/10"></div>
      <div class="relative z-10 flex w-full flex-col items-center gap-4 px-6 py-10 text-center">
        <.dynamic_icon
          :if={non_empty_string(Map.get(@section, "icon"))}
          name={Map.get(@section, "icon")}
          class="size-12 text-white/90"
        />
        <h2 class="text-2xl font-bold tracking-normal text-white drop-shadow sm:text-3xl">
          {Map.get(@section, "title", "")}
        </h2>
        <div class="max-w-3xl text-base leading-relaxed text-white/85 drop-shadow">
          {rich_text(Map.get(@section, "text", ""))}
        </div>
        <div :if={has_buttons?(@section)} class="pt-1">
          <.buttons buttons={Map.get(@section, "buttons", [])} />
        </div>
      </div>
    </section>
    """
  end

  # `"media_layout": "bleed"` is the hero's banner treatment applied to a
  # section: the media spans the whole VIEWPORT (breaking out of the centered
  # content container) and the title/text sit on top of it, so a run of
  # screenshots reads as one continuous piece with the hero.
  #
  # `self-start` is load-bearing: the parent section centers its items, and
  # centring an over-wide item fights the negative margin, landing the block
  # half off screen. `50%` resolves against the content box and `50vw`
  # against the viewport, so the margin cancels whatever padding and
  # centring the container applies.
  def section(%{section: %{"media_layout" => "bleed"}} = assigns) do
    ~H"""
    <%!-- Cancels the sections grid's `gap-y-4` so consecutive banners butt
          up against each other — a run of full-bleed screenshots should read
          as one continuous strip, not as cards with alleys between them.
          Only from the SECOND banner on: a symmetric `-my-2` would also pull
          the first one up into whatever precedes it (the hero). --%>
    <div class="w-screen self-start [&:not(:first-child)]:-mt-4 ml-[calc(50%-50vw)]">
      <.cover_banner
        item={@section}
        heading="h2"
        eager={false}
        class={bleed_height_class(@section)}
      />
    </div>
    """
  end

  # `"media_layout": "full"` stacks the section: media across the whole width
  # (16:9 art keeps its shape — no aspect-square box), then centered text and
  # buttons. Media stays optional, so full-layout also covers text-only or
  # icon-only sections.
  def section(%{section: %{"media_layout" => "full"}} = assigns) do
    ~H"""
    <section class={[
      "flex w-full flex-col items-center justify-center gap-6",
      section_height_class(@section)
    ]}>
      <.media :if={has_media?(@section)} item={@section} variant="full" columns={@columns} />
      <div class="flex w-full flex-col items-center gap-4 text-center">
        <h2 class="text-2xl font-bold tracking-normal sm:text-3xl">
          {Map.get(@section, "title", "")}
        </h2>
        <div class="max-w-3xl text-base leading-relaxed text-muted">
          {rich_text(Map.get(@section, "text", ""))}
        </div>
        <.host_component :if={has_component?(@section)} section={@section} />
        <.link_chips :if={has_links?(@section)} links={Map.get(@section, "links")} align="center" />
        <.card_grid :if={has_cards?(@section)} cards={Map.get(@section, "cards")} />
        <.faq
          :if={section_faq(@section) != []}
          entries={section_faq(@section)}
          class="w-full max-w-3xl"
        />
        <div :if={has_buttons?(@section)} class="pt-1">
          <.buttons buttons={Map.get(@section, "buttons", [])} />
        </div>
      </div>
    </section>
    """
  end

  def section(assigns) do
    ~H"""
    <section class={[
      "grid w-full gap-6 md:gap-x-8 md:gap-y-4",
      "items-center",
      section_height_class(@section),
      grid_class(@section, "section")
    ]}>
      <div class={["flex items-center", media_order_class(@section)]}>
        <.media item={@section} variant="section" columns={@columns} />
      </div>
      <div class={[
        "flex flex-col gap-4 md:justify-center md:gap-5 md:pt-6",
        section_text_frame_class(@section),
        text_order_class(@section),
        text_align_class(@section)
      ]}>
        <h2 class="text-2xl font-bold tracking-normal sm:text-3xl">
          {Map.get(@section, "title", "")}
        </h2>
        <div class="text-base leading-relaxed text-muted">
          {rich_text(Map.get(@section, "text", ""))}
        </div>
        <.host_component :if={has_component?(@section)} section={@section} />
        <.link_chips :if={has_links?(@section)} links={Map.get(@section, "links")} />
        <.card_grid :if={has_cards?(@section)} cards={Map.get(@section, "cards")} />
        <.faq
          :if={section_faq(@section) != []}
          entries={section_faq(@section)}
        />
        <div :if={has_buttons?(@section)} class="pt-1 md:pt-2">
          <.buttons buttons={Map.get(@section, "buttons", [])} />
        </div>
      </div>
    </section>
    """
  end

  def rich_text(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> then(fn escaped ->
      Regex.replace(@link_pattern, escaped, fn _match, label, href ->
        if safe_href?(href) do
          ~s(<a href="#{href}" class="link link-primary">#{label}</a>)
        else
          "#{label} (#{href})"
        end
      end)
    end)
    |> then(&Regex.replace(@bold_pattern, &1, "<strong>\\1</strong>"))
    |> then(&Regex.replace(@italic_pattern, &1, "<em>\\1</em>"))
    |> Phoenix.HTML.raw()
  end

  def rich_text(_), do: Phoenix.HTML.raw("")

  defp content_width_class, do: "max-w-2xl md:max-w-3xl lg:max-w-4xl xl:max-w-6xl"

  defp grid_class(item, variant) do
    width = media_width(item, variant)
    desktop_position = desktop_image_position(item)

    case {width, desktop_position} do
      {"third", "right"} -> "md:grid-cols-[minmax(0,1.2fr)_minmax(0,0.8fr)]"
      {"third", _} -> "md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]"
      {"wide", "right"} -> "md:grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)]"
      {"wide", _} -> "md:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]"
      _ -> "md:grid-cols-2"
    end
  end

  # `svh`, not `dvh`: section heights set the page's total height, and `dvh`
  # re-resolves whenever the dynamic viewport changes (mobile URL bar showing
  # or hiding, chrome settling during load). That moves every section, so a
  # scroll position the browser restores on reload lands at the wrong offset
  # and visibly jumps once layout settles. `svh` is fixed for the session.
  defp bleed_height_class(section) do
    case section_height(section) do
      value when value in ["compact", "sm", "small"] -> "min-h-[40svh]"
      value when value in ["full", "screen", "100", "100%"] -> "min-h-[100dvh]"
      _ -> "min-h-[50svh]"
    end
  end

  defp section_height_class(section) do
    case section_height(section) do
      value when value in ["compact", "sm", "small"] ->
        "py-8"

      value when value in ["half", "50", "50%"] ->
        "min-h-[calc(50svh-2.5rem)] py-8"

      value when value in ["full", "screen", "100", "100%"] ->
        "min-h-[calc(100svh-5rem)] py-12"

      _ ->
        "py-8"
    end
  end

  defp section_height(section), do: Map.get(section, "height", "compact")

  # `"sections_columns": 2` lays the sections out two-up from `md` and stays
  # one-up below it. A list page \u2014 a blog index, say \u2014 gets longer with every
  # entry, and a column of full-width rows is a lot of scrolling to see what is
  # there; a hero plus a two-column grid shows twice as much per screen.
  #
  # Opt-in, and only 1 or 2. Three across leaves each card too narrow for a
  # title and a sentence at the widths this grid actually runs at, and a page
  # that does not ask for columns renders exactly as it did before.
  defp sections_columns(page) do
    case Map.get(page, "sections_columns") do
      2 -> 2
      "2" -> 2
      _ -> 1
    end
  end

  defp sections_columns_class(2), do: "gap-x-4 md:grid-cols-2"
  defp sections_columns_class(_), do: nil

  defp background_icon_bands(sections) when is_list(sections), do: max(3, length(sections) + 2)

  defp placement_side_style(%{left: left}), do: "left: #{left}%"
  defp placement_side_style(%{right: right}), do: "right: #{right}%"

  defp background_icon_delay(%{delay: delay}, band) when is_number(delay), do: delay + band * 0.35
  defp background_icon_delay(_placement, band), do: band * 0.35

  defp sections_with_page_defaults(page) do
    default_height = Map.get(page, "sections_height")

    page
    |> Map.get("sections", [])
    |> case do
      sections when is_list(sections) ->
        Enum.map(sections, fn
          section when is_map(section) ->
            Map.put_new(section, "height", default_height || "compact")

          section ->
            section
        end)

      _ ->
        []
    end
  end

  defp media_order_class(item) do
    [
      if(Map.get(item, "image_position_mobile", "top") == "bottom",
        do: "order-2",
        else: "order-1"
      ),
      if(desktop_image_position(item) == "right", do: "md:order-2", else: "md:order-1")
    ]
  end

  defp text_order_class(item) do
    [
      if(Map.get(item, "image_position_mobile", "top") == "bottom",
        do: "order-1",
        else: "order-2"
      ),
      if(desktop_image_position(item) == "right", do: "md:order-1", else: "md:order-2")
    ]
  end

  defp text_align_class(item) do
    case Map.get(item, "text_align", "center") do
      "left" -> "text-start items-start"
      "right" -> "text-end items-end"
      _ -> "text-center items-center"
    end
  end

  defp image_config(item) do
    case Map.get(item, "image") do
      image when is_map(image) ->
        light = non_empty_string(Map.get(image, "light"))
        dark = non_empty_string(Map.get(image, "dark"))
        {natural_width, natural_height} = image_dimensions(light || dark)

        portrait = non_empty_string(Map.get(image, "portrait"))
        portrait_dark = non_empty_string(Map.get(image, "portrait_dark"))
        widths = image_widths(Map.get(image, "widths"))
        source_width = positive_int(Map.get(image, "width")) || natural_width

        %{
          light: image_src(light),
          dark: image_src(dark),
          # Optional narrow-viewport art. Landscape captures shrink to an
          # unreadable strip on a phone, so a page can ship a portrait cut and
          # the renderer swaps on breakpoint the same way it swaps on theme.
          portrait: image_src(portrait),
          portrait_dark: image_src(portrait_dark),
          alt: Map.get(image, "alt", ""),
          width: positive_int(Map.get(image, "width")) || natural_width,
          height: positive_int(Map.get(image, "height")) || natural_height,
          light_srcset: image_srcset(light, widths, source_width),
          dark_srcset: image_srcset(dark, widths, source_width),
          sizes: non_empty_string(Map.get(image, "sizes"))
        }

      _ ->
        empty_image_config()
    end
  end

  defp empty_image_config do
    %{
      light: nil,
      dark: nil,
      portrait: nil,
      portrait_dark: nil,
      alt: "",
      width: nil,
      height: nil,
      light_srcset: nil,
      dark_srcset: nil,
      sizes: nil
    }
  end

  # `"widths": [480, 960]` on an image opts it into a srcset. The variants are
  # found by convention — `main.webp` + 480 is `main-480.webp` — so the config
  # names one file and `mix host.responsive_images` generates the rest.
  defp image_widths(widths) when is_list(widths) do
    widths
    |> Enum.map(&positive_int/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp image_widths(_widths), do: []

  # A width whose file is missing is dropped rather than emitted: a 404 inside
  # a srcset is not a fallback to `src`, it is a broken image on whichever
  # viewport happened to pick that candidate.
  defp image_srcset(path, widths, source_width) do
    path = non_empty_string(path)

    if is_nil(path) or widths == [] do
      nil
    else
      widths
      |> Enum.filter(&variant_exists?(path, &1))
      |> Enum.map(&{width_variant_path(path, &1), &1})
      |> with_source_candidate(path, source_width)
      |> Enum.map_join(", ", fn {candidate, width} -> "#{image_src(candidate)} #{width}w" end)
      |> non_empty_string()
    end
  end

  # The full-size original has to be a candidate too. Once `srcset` carries `w`
  # descriptors the browser ignores `src` entirely when choosing — it is only a
  # fallback for clients without srcset support — so a list of downscaled
  # variants alone caps the image at the widest variant and any denser viewport
  # upscales it. `mix host.responsive_images` never writes a variant at or above
  # the source width (that would be an upscale), which is exactly why the source
  # belongs here rather than as another width in the config.
  #
  # Prepended, not appended: those same `w` descriptors are what the browser
  # picks by, so the order of the list carries no meaning and there is nothing
  # to be gained by walking it to reach the end.
  #
  # No variants exist means the image opted out in practice — emit no srcset at
  # all rather than a one-candidate list that just restates `src`.
  defp with_source_candidate([], _path, _source_width), do: []

  defp with_source_candidate(candidates, path, source_width) do
    if is_integer(source_width) and
         Enum.all?(candidates, fn {_candidate, width} -> width < source_width end) do
      [{path, source_width} | candidates]
    else
      candidates
    end
  end

  defp width_variant_path(path, width) do
    ext = Path.extname(path)
    String.replace_suffix(path, ext, "-#{width}#{ext}")
  end

  # Only a variant from the directory that serves the original: a project that
  # replaces the engine's `banner.webp` with its own must not have the engine's
  # `banner-480.webp`, a cut of a different picture, offered in its srcset.
  defp variant_exists?(path, width) do
    path
    |> width_variant_path(width)
    |> ProjectStatic.derived_from?(path)
  end

  # How wide the media column is at each breakpoint, so the browser takes the
  # smallest candidate that fills it instead of assuming `100vw`. A share of
  # the viewport overshoots: the content box stops growing at
  # `content_width_class/0`'s caps, so at 1366px a "third" column is 422px
  # where `45vw` claimed 615, and a 2x screen fetched the 1440w file for it.
  #
  # Each box is `{min_width, content_width, grid_gap}`: the capped width less
  # the container's padding (`px-4 sm:px-6 lg:px-8` around sections,
  # `px-6 sm:px-8 lg:px-12` around the hero), and the gap between media and
  # text (`md:gap-x-8`; the hero's `gap-8 lg:gap-12`). Below `md` the grid is
  # one column, so the image takes the whole box. Keep these in step with
  # the classes they are read from.
  @section_boxes [{1280, 1088, 32}, {1024, 832, 32}, {768, 720, 32}]
  @section_phone "(min-width: 672px) 624px, calc(100vw - 32px)"
  @hero_boxes [{1280, 1056, 48}, {1024, 800, 48}, {768, 704, 32}]
  @hero_phone "(min-width: 672px) 608px, calc(100vw - 48px)"
  # `sections_columns_class(2)`'s `gap-x-4` between two-up sections.
  @sections_columns_gap 16

  defp media_sizes(item, "hero", _columns),
    do: column_sizes(@hero_boxes, @hero_phone, column_share(media_width(item, "hero")))

  defp media_sizes(_item, "full", columns),
    do: column_sizes(two_up(@section_boxes, columns), @section_phone, :whole)

  defp media_sizes(item, variant, columns),
    do:
      column_sizes(
        two_up(@section_boxes, columns),
        @section_phone,
        column_share(media_width(item, variant))
      )

  defp column_sizes(boxes, phone, share) do
    boxes
    |> Enum.map(fn {min_width, box, gap} ->
      width = if share == :whole, do: box, else: (box - gap) * share
      "(min-width: #{min_width}px) #{ceil(width)}px"
    end)
    |> Enum.concat([phone])
    |> Enum.join(", ")
  end

  defp two_up(boxes, 2),
    do:
      Enum.map(boxes, fn {min_width, box, gap} ->
        {min_width, (box - @sections_columns_gap) / 2, gap}
      end)

  defp two_up(boxes, _columns), do: boxes

  # The media column's fraction of the grid, from `grid_class/2`'s `fr` pairs.
  defp column_share("third"), do: 0.4
  defp column_share("wide"), do: 0.575
  defp column_share(_half), do: 0.5

  # A `"video"` item renders in place of `"image"`, so the same slot in a hero
  # or section holds either. `src` and `poster` go through `image_src/1` for
  # the content-hashed `?v=` query — static responses are served
  # `immutable, max-age=1y`, so an unversioned path would pin a recut trailer
  # in browser caches for a year.
  defp video_config(item) do
    case Map.get(item, "video") do
      video when is_map(video) ->
        poster = non_empty_string(Map.get(video, "poster"))
        {natural_width, natural_height} = image_dimensions(poster)

        %{
          src: image_src(non_empty_string(Map.get(video, "src"))),
          poster: image_src(poster),
          alt: Map.get(video, "alt", ""),
          width: positive_int(Map.get(video, "width")) || natural_width,
          height: positive_int(Map.get(video, "height")) || natural_height,
          preload: video_preload(Map.get(video, "preload")),
          muted: Map.get(video, "muted", true) != false
        }

      _ ->
        empty_video_config()
    end
  end

  defp empty_video_config do
    %{
      src: nil,
      poster: nil,
      alt: "",
      width: nil,
      height: nil,
      preload: "metadata",
      muted: true
    }
  end

  defp video_preload(value) when value in ["none", "metadata", "auto"], do: value
  defp video_preload(_value), do: "metadata"

  defp section_text_frame_class(section) do
    if image_config(section).light || video_config(section).src do
      "md:min-h-[min(42dvh,24rem)]"
    else
      "md:min-h-48"
    end
  end

  # Only reachable from the full-layout section clause, whose pattern already
  # guarantees a map.
  defp has_media?(item) do
    image_config(item).light != nil or video_config(item).src != nil or
      non_empty_string(Map.get(item, "icon")) != nil
  end

  defp has_buttons?(item) when is_map(item) do
    item
    |> Map.get("buttons", [])
    |> case do
      buttons when is_list(buttons) -> Enum.any?(buttons, &valid_button?/1)
      _ -> false
    end
  end

  defp has_buttons?(_item), do: false

  defp non_empty_string(value) when is_binary(value) and value != "", do: value
  defp non_empty_string(_value), do: nil

  defp positive_int(value) when is_integer(value) and value > 0, do: value

  defp positive_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp positive_int(_value), do: nil

  defp image_src(path) do
    case non_empty_string(path) do
      nil -> nil
      path -> path |> optimized_image_path() |> versioned()
    end
  end

  defp versioned(path), do: GamendWeb.SRI.versioned_path(path) || path

  # The WebP `mix host.optimize_images` made from a PNG or JPEG, when it was
  # made from this one: a project's own `/images/logo.png` must not be swapped
  # for the engine's WebP of the engine's logo.
  defp optimized_image_path(path) do
    generated = generated_image_path(path)

    if generated && ProjectStatic.derived_from?(generated, path), do: generated, else: path
  end

  defp generated_image_path(path) do
    clean_path = URI.parse(path).path || path

    with true <- String.starts_with?(clean_path, "/images/"),
         false <- String.contains?(clean_path, "/generated/"),
         ext when ext in [".png", ".jpg", ".jpeg"] <-
           clean_path |> Path.extname() |> String.downcase() do
      rel =
        clean_path
        |> String.trim_leading("/images/")
        |> Path.rootname()

      "/images/generated/#{rel}.webp"
    else
      _ -> nil
    end
  end

  # `path_for/1` takes the path as configured, query and all, and answers nil
  # for an absolute URL rather than measuring a local file that shares its path.
  defp image_dimensions(path) do
    case ProjectStatic.path_for(non_empty_string(path)) do
      file_path when is_binary(file_path) -> read_image_dimensions(file_path)
      nil -> {nil, nil}
    end
  end

  defp read_image_dimensions(file_path) do
    case File.read(file_path) do
      {:ok,
       <<0x89, "PNG\r\n", 0x1A, "\n", _length::32, "IHDR", width::32, height::32, _::binary>>} ->
        {width, height}

      {:ok, <<"RIFF", _size::32, "WEBP", rest::binary>>} ->
        webp_dimensions(rest)

      _ ->
        {nil, nil}
    end
  end

  # Presentation art is WebP, and a source whose dimensions we cannot read gets
  # no srcset candidate of its own — so the three container flavours all have to
  # be understood here, not just the lossy one. Every field is little-endian,
  # and VP8L/VP8X store each axis minus one.
  defp webp_dimensions(<<"VP8 ", _size::32, _frame_tag::24, 0x9D, 0x01, 0x2A, raw::binary>>) do
    case raw do
      <<width::little-16, height::little-16, _::binary>> ->
        # The top two bits of each 16-bit field are the scaling hint.
        {Bitwise.band(width, 0x3FFF), Bitwise.band(height, 0x3FFF)}

      _ ->
        {nil, nil}
    end
  end

  defp webp_dimensions(<<"VP8L", _size::32, 0x2F, bits::little-32, _::binary>>) do
    {Bitwise.band(bits, 0x3FFF) + 1, Bitwise.band(Bitwise.bsr(bits, 14), 0x3FFF) + 1}
  end

  defp webp_dimensions(
         <<"VP8X", _size::32, _flags::32, width::little-24, height::little-24, _::binary>>
       ) do
    {width + 1, height + 1}
  end

  defp webp_dimensions(_rest), do: {nil, nil}

  defp media_width(item, "hero"), do: Map.get(item, "media_width", "half")
  defp media_width(item, _variant), do: Map.get(item, "media_width", "third")

  defp media_size(item, variant) do
    case Map.get(item, "media_size", variant) do
      value when value in ["hero", "section", "full", "bleed"] -> value
      _ -> variant
    end
  end

  defp desktop_image_position(item), do: Map.get(item, "image_position_desktop", "left")

  defp media_class("hero", _image), do: "block max-h-[58dvh] w-full rounded-lg object-contain"

  defp media_class("full", _image), do: "block max-h-[70dvh] w-full rounded-lg object-contain"

  # Edge to edge: no rounding (it meets both screen edges) and no height
  # cap beyond the viewport itself.
  defp media_class("bleed", _image), do: "block max-h-[85dvh] w-full object-contain"

  # The box takes the image's own shape from its `width`/`height`. A square
  # box around 16:9 art left a band above and below it (140px a screenshot
  # on a desktop home page), and audits read the box against the picture as
  # a distorted image. Only an image whose size could not be read keeps the
  # square, so the slot still holds its place before a lazy image loads.
  defp media_class("section", %{width: width, height: height})
       when is_integer(width) and is_integer(height),
       do: "block max-h-[42dvh] w-full rounded-lg object-contain"

  defp media_class("section", _image),
    do: "block aspect-square max-h-[42dvh] w-full rounded-lg object-contain"

  # No `aspect-square` here, unlike `media_class/2` — video is natively
  # widescreen and squaring the box would letterbox it into a fraction of the
  # slot.
  defp media_video_class("hero"),
    do: "block max-h-[58dvh] w-full rounded-lg object-contain"

  defp media_video_class("full"),
    do: "block max-h-[70dvh] w-full rounded-lg object-contain"

  defp media_video_class("bleed"),
    do: "block max-h-[85dvh] w-full object-contain"

  defp media_video_class("section"),
    do: "block max-h-[42dvh] w-full rounded-lg object-contain"

  defp media_shell_class,
    do: "flex w-full items-center justify-center"

  defp button_class(button) do
    base =
      "group flex min-h-11 w-full items-center justify-center gap-2.5 rounded-lg px-5 py-2.5 text-base font-semibold transition hover:scale-[1.02] active:scale-[0.98] sm:w-auto sm:min-w-36"

    style =
      case Map.get(button, "style", "default") do
        "primary" ->
          "bg-primary text-primary-content shadow-lg hover:bg-primary/90"

        "secondary" ->
          "bg-secondary text-secondary-content shadow-lg hover:bg-secondary/90"

        "accent" ->
          "bg-accent text-accent-content shadow-lg hover:bg-accent/90"

        _ ->
          "border border-base-300/85 bg-base-100/88 text-base-content shadow-lg shadow-black/6 backdrop-blur-md hover:bg-base-100"
      end

    [base, style]
  end

  # On a coloured button the badge takes the button's content colour, or it
  # vanishes into the fill.
  defp badge_class(button) do
    case Map.get(button, "style", "default") do
      style when style in ["primary", "secondary", "accent"] ->
        "border-current/40 bg-current/15 text-current"

      _ ->
        "badge-primary"
    end
  end

  defp valid_button?(%{"disabled" => true, "label" => label}) do
    is_binary(label) and label != ""
  end

  defp valid_button?(%{"href" => href, "label" => label}) do
    is_binary(href) and href != "" and is_binary(label) and label != ""
  end

  defp valid_button?(_button), do: false

  defp presentation_page?(%{"hero" => hero}) when is_map(hero), do: true
  defp presentation_page?(%{"sections" => sections}) when is_list(sections), do: true
  defp presentation_page?(_page), do: false

  defp normalize_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> case do
      "" -> "/"
      value -> if(String.starts_with?(value, "/"), do: value, else: "/" <> value)
    end
    |> String.trim_trailing("/")
    |> case do
      "" -> "/"
      value -> value
    end
  end

  defp normalize_path(_path), do: "/"

  defp safe_href?(href) when is_binary(href) do
    String.starts_with?(href, "/") or String.starts_with?(href, "http://") or
      String.starts_with?(href, "https://") or String.starts_with?(href, "mailto:")
  end

  defp safe_href?(_href), do: false
end
