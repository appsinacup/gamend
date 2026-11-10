defmodule GamendWeb.AdminLive.Theme do
  @moduledoc """
  `/admin/theme`: the theme as this server resolved it. Branding images and
  their dark variants, the copy, the configured pages, navigation and footer,
  and the raw JSON they came from. Read-only: a theme is a file the host owns.
  """
  use GamendWeb, :live_view

  alias Gamend.Content
  alias Gamend.Theme.JSONConfig

  require GamendWeb.NavAuth, as: NavAuth

  @nav_lists [
    {"Primary Nav", "primary_links"},
    {"Guest Nav", "guest_links"},
    {"Authenticated Nav", "authenticated_links"},
    {"Account Menu", "account_links"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    theme = GamendWeb.Layouts.resolve_theme() || %{}

    {:ok,
     assign(socket,
       page_title: "Admin · Theme",
       theme: theme,
       raw_theme: JSONConfig.get_theme(),
       config_path: JSONConfig.runtime_path(),
       content_paths: [
         {"Blog", Content.path(:blog)},
         {"Changelog", Content.path(:changelog)},
         {"Roadmap", Content.path(:roadmap)}
       ],
       nav_lists: nav_lists(theme),
       pages: pages(theme),
       footer_sections: get_in(theme, ["footer", "sections"]) || []
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.admin_header page="/admin/theme">
          <:subtitle>
            What the theme resolved to. Change the file and restart to change it.
          </:subtitle>
        </.admin_header>

        <div id="theme-source" class="card bg-base-200 shadow">
          <div class="card-body gap-1">
            <h2 class="card-title text-lg">
              Source
              <span class={["badge badge-sm", (@config_path && "badge-success") || "badge-ghost"]}>
                {if @config_path, do: "Configured", else: "Default"}
              </span>
            </h2>
            <p class="font-mono text-sm break-all">
              GAMEND_CONTENT_THEME_CONFIG: {@config_path || "<unset>"}
            </p>
          </div>
        </div>

        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">Branding</h2>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <.asset label="Logo" path={@theme["logo"]} dark={logo_dark(@theme)} class="h-12" />
              <.asset
                label="Favicon"
                path={@theme["favicon"]}
                dark={dark_path(@theme["favicon"])}
                class="h-8"
              />
              <.asset
                label="Banner"
                path={@theme["banner"]}
                dark={dark_path(@theme["banner"])}
                class="h-16"
              />
            </div>

            <h3 class="font-semibold mt-4">Fullscreen hero</h3>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.hero label="Light" path="/images/fullscreen.png" />
              <.hero label="Dark" path="/images/fullscreen_dark.png" />
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow">
          <div class="card-body gap-1">
            <h2 class="card-title text-lg">Copy and content</h2>
            <.line label="Title">{Map.get(@theme, "title", "—")}</.line>
            <.line label="Tagline">{Map.get(@theme, "tagline", "—")}</.line>
            <.line label="Description">{Map.get(@theme, "description", "—")}</.line>
            <.line label="CSS" mono>
              {@theme["css"] || "/assets/css/app.css (loaded by host layout)"}
            </.line>
            <.line :for={{label, path} <- @content_paths} label={label} mono>{path || "—"}</.line>
          </div>
        </div>

        <div
          :if={@pages != [] or @nav_lists != [] or @footer_sections != []}
          class="card bg-base-200 shadow"
        >
          <div class="card-body">
            <h2 class="card-title text-lg">Pages and navigation</h2>

            <.chips :if={@pages != []} title={"Pages (#{length(@pages)})"}>
              <span :for={{key, page} <- @pages} class="badge badge-outline gap-1 h-auto py-1">
                <span>{key}</span>
                <span class="text-muted">{Map.get(page, "path", "—")}</span>
                <span class="text-muted">
                  ({ngettext(
                    "%{count} section",
                    "%{count} sections",
                    length(Map.get(page, "sections", []))
                  )})
                </span>
              </span>
            </.chips>

            <.chips :for={{title, links} <- @nav_lists} title={"#{title} (#{length(links)})"}>
              <span :for={link <- links} class="badge badge-ghost gap-1 h-auto py-1">
                <span>{nav_label(link)}</span>
                <span class="text-muted">{nav_path(link)}</span>
                <span :if={nav_auth(link)} class="text-muted">({nav_auth(link)})</span>
              </span>
            </.chips>

            <.chips
              :if={@footer_sections != []}
              title={"Footer Sections (#{length(@footer_sections)})"}
            >
              <span :for={section <- @footer_sections} class="badge badge-ghost gap-1 h-auto py-1">
                <span>{section["title"]}</span>
                <span class="text-muted">
                  {ngettext(
                    "%{count} link",
                    "%{count} links",
                    length(Map.get(section, "links", []))
                  )}
                </span>
              </span>
            </.chips>
          </div>
        </div>

        <details id="theme-raw-json" class="card bg-base-200 shadow">
          <summary class="card-body cursor-pointer font-semibold">Raw JSON</summary>
          <pre class="px-6 pb-6 text-xs font-mono whitespace-pre-wrap break-words max-h-96 overflow-auto">{Jason.encode!(@raw_theme, pretty: true)}</pre>
        </details>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :path, :string, default: nil
  attr :dark, :string, default: nil, doc: "where its dark variant would be"
  attr :class, :string, required: true

  defp asset(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1 text-center">
      <span class="text-xs font-semibold text-muted">{@label}</span>
      <%= if @path do %>
        <img src={@path} alt={@label} class={[@class, "w-auto rounded-field"]} />
        <span class="text-xs text-muted break-all">{@path}</span>
        <%= if exists?(@dark) do %>
          <span class="text-xs font-semibold text-muted mt-1">Dark</span>
          <img
            src={@dark}
            alt={"#{@label}, dark"}
            class={[@class, "w-auto rounded-field bg-neutral p-1"]}
          />
          <span class="text-xs text-muted break-all">{@dark}</span>
        <% else %>
          <span class="text-xs text-muted mt-1">Dark: not found</span>
        <% end %>
      <% else %>
        <span class="text-xs text-muted">—</span>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :path, :string, required: true

  defp hero(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1 text-center">
      <span class="text-xs font-semibold text-muted">{@label}</span>
      <img
        :if={exists?(@path)}
        src={@path}
        alt={"Fullscreen hero, #{@label}"}
        class="w-full max-w-56 h-auto rounded-field"
      />
      <span class="text-xs text-muted break-all">
        {@path}{if !exists?(@path), do: " — not found"}
      </span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :mono, :boolean, default: false
  slot :inner_block, required: true

  defp line(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <span class="text-xs font-semibold text-muted w-24 shrink-0">{@label}</span>
      <span class={[@mono && "font-mono text-xs break-all", !@mono && "text-sm"]}>
        {render_slot(@inner_block)}
      </span>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp chips(assigns) do
    ~H"""
    <div>
      <h3 class="text-xs font-semibold text-muted">{@title}</h3>
      <div class="mt-1 flex flex-wrap gap-2 text-xs">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp pages(theme) do
    case Map.get(theme, "pages", %{}) do
      pages when is_map(pages) -> Enum.sort_by(pages, &elem(&1, 0))
      _not_a_map -> []
    end
  end

  defp nav_lists(theme) do
    navigation = Map.get(theme, "navigation", %{})

    for {title, key} <- @nav_lists, links = Map.get(navigation, key, []), links != [] do
      {title, links}
    end
  end

  # Convention: `file.ext` → `file_dark.ext`. The theme names its dark mark when
  # the light one's name does not follow it.
  defp logo_dark(theme), do: theme["logo_dark"] || dark_path(theme["logo"])

  defp dark_path(nil), do: nil
  defp dark_path(path), do: String.replace(path, ~r/\.(\w+)$/, "_dark.\\1")

  # Looked up the way the endpoint serves it: a project's static overlay first,
  # then the apps' priv/static.
  defp exists?(nil), do: false
  defp exists?(path), do: GamendWeb.ProjectStatic.path_for(path) != nil

  defp nav_label(%{"label" => label, "items" => items}) when is_list(items),
    do: "#{label} (#{length(items)})"

  defp nav_label(%{"label" => label}) when is_binary(label), do: label
  defp nav_label(_entry), do: "Unnamed"

  defp nav_path(%{"items" => _items}), do: "dropdown"
  defp nav_path(%{"href" => href}) when is_binary(href), do: href
  defp nav_path(_entry), do: "—"

  defp nav_auth(%{"admin_only" => true}), do: NavAuth.admin()
  defp nav_auth(%{"auth" => auth}) when is_binary(auth) and auth != "", do: auth
  defp nav_auth(_entry), do: nil
end
