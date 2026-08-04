defmodule GamendWeb.HostLayoutShell do
  @moduledoc false

  use GamendWeb, :html

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_path, :string, default: nil
  attr :current_query, :string, default: ""
  attr :flush, :boolean, default: false
  attr :theme, :map, required: true
  attr :navigation, :map, default: %{}
  attr :footer, :map, default: %{}
  attr :background_icons, :list, default: []
  attr :notif_unread_count, :integer, default: 0
  attr :locale, :string, required: true
  attr :known_locales, :list, default: []
  attr :breadcrumbs, :list, default: []

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.background_icons background_icons={@background_icons} current_path={@current_path} />
    <div class={["flex flex-col", if(@flush, do: "h-dvh overflow-hidden relative", else: "min-h-dvh")]}>
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
        class={[
          "navbar z-50",
          if(@flush,
            do: "absolute top-0 left-0 right-0 pl-4 sm:pl-6 lg:pl-8 pr-14",
            else: "sticky top-0 shrink-0 px-4 sm:px-6 lg:px-8"
          ),
          if(@flush,
            do: "bg-base-100/90 backdrop-blur-md",
            else: "bg-transparent backdrop-blur-md border-base-200/20"
          )
        ]}
      >
        <% title = Map.get(@theme, "title") %>
        <% tagline = Map.get(@theme, "tagline") %>
        <% logo = Map.get(@theme, "logo") %>
        <div class="flex-1">
          <a href={~p"/"} class="flex-1 flex w-fit items-center gap-2">
            <img
              src={GamendWeb.SRI.versioned_path(logo) || logo}
              width="36"
              height="36"
              alt={title}
              decoding="async"
            />
            <span class="text-lg font-bold">{title}</span>
            <%= if tagline && tagline != "" do %>
              <span class="text-sm opacity-80 ml-1 hidden xl:inline">{tagline}</span>
            <% end %>
          </a>
        </div>
        <div class="flex-none">
          <GamendWeb.HostLayoutNavigation.desktop_nav
            current_scope={@current_scope}
            current_path={@current_path}
            current_query={@current_query}
            navigation={@navigation}
            notif_unread_count={@notif_unread_count}
            locale={@locale}
            known_locales={@known_locales}
          />

          <GamendWeb.HostLayoutNavigation.mobile_nav
            current_scope={@current_scope}
            current_path={@current_path}
            current_query={@current_query}
            navigation={@navigation}
            notif_unread_count={@notif_unread_count}
            locale={@locale}
            known_locales={@known_locales}
          />
        </div>
      </header>

      <GamendWeb.HostLayoutNavigation.language_modal
        :if={length(@known_locales) > 1}
        locale={@locale}
        current_path={@current_path}
        current_query={@current_query}
        known_locales={@known_locales}
      />

      <%= if @flush do %>
        <div class="flex-1 min-h-0 relative">
          {render_slot(@inner_block)}
        </div>
        <GamendWeb.HostLayouts.flash_group flash={@flash} />
      <% else %>
        <main class="relative z-[2] px-4 py-4 sm:px-6 lg:px-8 flex-1">
          <div class="mx-auto max-w-2xl md:max-w-3xl lg:max-w-4xl xl:max-w-6xl space-y-4">
            <.breadcrumbs trail={@breadcrumbs} />
            {render_slot(@inner_block)}
          </div>
        </main>

        <GamendWeb.HostLayouts.flash_group flash={@flash} />
        <footer class="px-4 py-8 sm:px-6 lg:px-8 text-sm text-base-content/70">
          <div class="mx-auto grid max-w-2xl gap-6 md:max-w-3xl md:grid-cols-2 lg:max-w-4xl xl:max-w-6xl xl:grid-cols-4">
            <section :for={section <- footer_sections(@footer)} class="space-y-2">
              <h2 class="text-sm font-semibold text-base-content">
                {section["title"]}
              </h2>
              <nav class="flex flex-col gap-1.5">
                <a
                  :for={link <- visible_footer_links(section, @current_scope)}
                  href={link["href"]}
                  target={if(link["external"], do: "_blank", else: nil)}
                  rel={if(link["external"], do: "noopener noreferrer", else: nil)}
                  class="w-fit hover:text-base-content hover:underline"
                >
                  {link["label"]}
                </a>
              </nav>
            </section>
          </div>
        </footer>
      <% end %>
    </div>
    """
  end

  attr :trail, :list, default: []

  @doc """
  The breadcrumb trail, as `{label, path}` pairs — the last one is the current
  page and carries a `nil` path.

  Renders nothing for a bare `[{"Home", nil}]`: a trail with no ancestors tells
  the reader nothing, and Google ignores a single-item `BreadcrumbList`.
  """
  def breadcrumbs(assigns) do
    ~H"""
    <nav :if={length(@trail) > 1} aria-label="Breadcrumb" class="text-sm text-base-content/60">
      <ol class="flex flex-wrap items-center gap-2">
        <li :for={{{label, path}, index} <- Enum.with_index(@trail)} class="flex items-center gap-2">
          <span :if={index > 0} aria-hidden="true">/</span>
          <.link :if={path} href={path} class="hover:text-primary transition-colors">
            {label}
          </.link>
          <span :if={is_nil(path)} aria-current="page" class="text-base-content/90">{label}</span>
        </li>
      </ol>
    </nav>
    """
  end


  defp footer_sections(%{"sections" => sections}) when is_list(sections), do: sections
  defp footer_sections(_footer), do: []

  # A footer link obeys the same `"auth"` rule as the nav: /store is behind
  # `require_authenticated_user`, so advertising it to a signed-out visitor
  # just sends them to an error.
  defp visible_footer_links(section, current_scope) do
    section
    |> Map.get("links", [])
    |> Enum.filter(&GamendWeb.HostLayoutNavigation.entry_visible?(&1, current_scope))
  end

  attr :background_icons, :list, default: []
  attr :current_path, :string, default: nil

  def background_icons(assigns) do
    ~H"""
    <%= if @background_icons != [] and @current_path not in ["/", "/play"] do %>
      <div class="fixed inset-0 overflow-hidden pointer-events-none z-[1]" aria-hidden="true">
        <%= for placement <- GamendWeb.HostLayouts.icon_placements(@background_icons) do %>
          <div
            class={[
              "absolute text-base-content [[data-theme=dark]_&]:text-white opacity-[0.08] [[data-theme=dark]_&]:opacity-[0.10]",
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
