defmodule GamendWeb.AdminComponents do
  @moduledoc """
  The admin console's page furniture: a heading, a coloured icon and a
  dashboard card. Imported wherever `use GamendWeb, :live_view` is, so core's
  pages and a host's (Forge, Polyglot, a fork) are the same shapes without
  restating a class. There is nothing to configure: a page says what it is
  where it draws itself.

  A core page names its table entry (`GamendWeb.AdminLive.Pages`):

      <.admin_header page="/admin/users">
        <:actions><button class="btn btn-sm">Export</button></:actions>
      </.admin_header>

  A host's page says the same three things itself:

      <.admin_header title="Builds" icon="hero-cube" color="violet" />

  and lists the page on `/admin` from its `GamendWeb.AdminCard` module, with
  the same `icon` and `color`.

  `color` is a name from `colors/0`, not a class: Tailwind writes only classes
  it reads in a source file, and each name's are written out below, in a file
  every host's stylesheet scans. An icon is any `hero-*` name; a host's is
  picked up from its own `lib`.
  """

  use Phoenix.Component

  import GamendWeb.CoreComponents, only: [back_link: 1, entity_card: 1, icon: 1, page_title: 1]

  alias GamendWeb.AdminLive.Pages

  @md "md"

  @default_icon "hero-squares-2x2"
  @default_color "slate"

  # Icons carry meaning, so they hold 3:1 against the tile in both themes
  # (RULES.md): the 700 shade on a light page, the 300 on a dark one.
  @colors %{
    "slate" => "bg-slate-500/15 text-slate-700 dark:text-slate-300",
    "sky" => "bg-sky-500/15 text-sky-700 dark:text-sky-300",
    "blue" => "bg-blue-500/15 text-blue-700 dark:text-blue-300",
    "indigo" => "bg-indigo-500/15 text-indigo-700 dark:text-indigo-300",
    "violet" => "bg-violet-500/15 text-violet-700 dark:text-violet-300",
    "pink" => "bg-pink-500/15 text-pink-700 dark:text-pink-300",
    "rose" => "bg-rose-500/15 text-rose-700 dark:text-rose-300",
    "orange" => "bg-orange-500/15 text-orange-700 dark:text-orange-300",
    "amber" => "bg-amber-500/15 text-amber-700 dark:text-amber-300",
    "lime" => "bg-lime-500/15 text-lime-700 dark:text-lime-300",
    "emerald" => "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
    "teal" => "bg-teal-500/15 text-teal-700 dark:text-teal-300",
    "cyan" => "bg-cyan-500/15 text-cyan-700 dark:text-cyan-300",
    "primary" => "bg-primary/15 text-primary",
    "secondary" => "bg-secondary/15 text-secondary",
    "accent" => "bg-accent/15 text-accent",
    "info" => "bg-info/15 text-info",
    "success" => "bg-success/15 text-success",
    "warning" => "bg-warning/15 text-warning",
    "error" => "bg-error/15 text-error"
  }

  @size_names ~w(sm md lg)

  @sizes %{
    "sm" => {"size-8", "size-4"},
    "md" => {"size-9", "size-5"},
    "lg" => {"size-11 sm:size-12", "size-6 sm:size-7"}
  }

  @doc "The names `color` takes: the palette's, then the theme's own tokens."
  @spec colors() :: [String.t()]
  def colors, do: Map.keys(@colors)

  attr :icon, :string, default: nil, doc: "a `hero-*` name"
  attr :color, :string, default: nil, doc: "a name from `colors/0`; an unknown one draws slate"
  attr :size, :string, default: @md, values: @size_names
  attr :class, :any, default: nil, doc: "layout only"

  @doc """
  A coloured square with an icon in it, what marks an admin page wherever it
  appears. Decoration beside words that name the page, so it is hidden from a
  screen reader.
  """
  def admin_icon(assigns) do
    {tile, glyph} = Map.fetch!(@sizes, assigns.size)

    assigns =
      assign(assigns,
        tile: tile,
        glyph: glyph,
        tint: Map.get(@colors, assigns.color, @colors[@default_color]),
        name: assigns.icon || @default_icon
      )

    ~H"""
    <span
      aria-hidden="true"
      class={["inline-flex shrink-0 items-center justify-center rounded-box", @tile, @tint, @class]}
    >
      <.icon name={@name} class={@glyph} />
    </span>
    """
  end

  attr :page, :string, default: nil, doc: "a core page's path in `GamendWeb.AdminLive.Pages`"
  attr :title, :string, default: nil, doc: "the page's name; a host's, or a core page's override"
  attr :icon, :string, default: nil
  attr :color, :string, default: nil

  attr :back, :any,
    default: "/admin",
    doc: "live path one step up; nil on the dashboard, which has no parent"

  slot :subtitle, doc: "one line under the title"
  slot :actions, doc: "what the page does as a whole, at the row's end"

  @doc """
  The top of every admin page: Back, the page's icon, its `<h1>`, an optional
  subtitle and the page's actions. The title is drawn by `page_title/1` and
  the arrow by `back_link/1`, the same two a public page uses, so an admin
  page differs from one only by the coloured mark.
  """
  def admin_header(assigns) do
    assigns = resolve(assigns)

    ~H"""
    <header class="mb-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
      <div class="flex min-w-0 items-center gap-3">
        <.back_link :if={@back} navigate={@back} />
        <.admin_icon icon={@icon} color={@color} size="lg" />
        <div class="min-w-0">
          <.page_title class="break-words">{@title}</.page_title>
          <p :if={@subtitle != []} class="mt-1 text-sm text-muted">{render_slot(@subtitle)}</p>
        </div>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :page, :string, default: nil, doc: "a core page's path; names the card and links to it"
  attr :title, :string, default: nil
  attr :icon, :string, default: nil
  attr :color, :string, default: nil
  attr :path, :string, default: nil, doc: "the page a click opens; `page` when not given"
  attr :value, :any, default: nil, doc: "the headline figure"
  attr :unit, :string, default: nil, doc: "a word after the figure: `plays`, `errors (1h)`"
  attr :value_class, :any, default: nil, doc: "the figure's colour, where it means something"
  attr :rest, :global
  slot :inner_block, doc: "the lines under the figure"

  @doc """
  One card on `/admin`: an `entity_card/1` with the page's coloured mark, a
  headline figure and the lines under it, so it is the site's card and not a
  look of its own. A click anywhere on it opens the page; a link in its lines
  sits above the stretched title and goes where it says. A host's cards
  (`GamendWeb.AdminCard`) are drawn with it.

  The link is a plain `href`: `live_nav.js` moves it over the open socket when
  the target is a LiveView of this session, and a host's card may just as well
  open a controller page, which `navigate` would break on.
  """
  def admin_card(assigns) do
    assigns = resolve(assigns)
    assigns = assign(assigns, :href, assigns.path || assigns.page)

    ~H"""
    <.entity_card title={@title} href={@href} {@rest}>
      <:mark><.admin_icon icon={@icon} color={@color} /></:mark>
      <div :if={@value != nil} class={["text-2xl font-bold", @value_class]}>
        {@value}<span :if={@unit} class="ml-1 text-sm font-normal text-muted">{@unit}</span>
      </div>
      <div :if={@inner_block != []} class="space-y-1 text-sm text-muted [&_a]:relative [&_a]:z-10">
        {render_slot(@inner_block)}
      </div>
    </.entity_card>
    """
  end

  # A page's own `title`, `icon` and `color` win over its table entry, so a
  # card can open a page under another name ("Activity" opens Analytics).
  defp resolve(%{page: nil} = assigns), do: assigns

  defp resolve(%{page: path} = assigns) do
    entry = Pages.fetch!(path)

    assign(assigns,
      title: assigns.title || entry.title,
      icon: assigns.icon || entry.icon,
      color: assigns.color || entry.color
    )
  end
end
