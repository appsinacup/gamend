defmodule GameServerWeb.HostLayouts do
  @moduledoc """
  Host-owned layout entrypoints and shared layout helpers.
  """

  use GameServerWeb, :html

  alias GameServer.Theme.JSONConfig
  alias GameServerWeb.HostLayoutShell

  @known_locales GameServerWeb.GettextSync.known_locales()

  @locale_labels %{
    "ar" => "العربية",
    "bg" => "български език",
    "cs" => "čeština",
    "da" => "Dansk",
    "de" => "Deutsch",
    "el" => "Ελληνικά",
    "en" => "English",
    "es" => "Español",
    "es_ES" => "Español (España)",
    "fi" => "suomi",
    "fr" => "Français",
    "hu" => "magyar",
    "id" => "Bahasa Indonesia",
    "it" => "Italiano",
    "ja" => "日本語",
    "ko" => "한국어",
    "nl" => "Nederlands",
    "no" => "Norsk",
    "pl" => "Polski",
    "pt" => "Português",
    "pt_BR" => "Português do Brasil",
    "ro" => "Română",
    "ru" => "Русский",
    "sv" => "Svenska",
    "th" => "ไทย",
    "tr" => "Türkçe",
    "uk" => "Українська",
    "vi" => "Tiếng Việt",
    "zh_CN" => "简体中文",
    "zh_TW" => "繁體中文"
  }

  embed_templates "host_layouts/*"

  @icon_slots [
    %{top: 13, left: 4, size: "size-9 sm:size-13", dur: 8, delay: 0},
    %{top: 12, right: 6, size: "size-8 sm:size-12", dur: 10, delay: 1},
    %{top: 21, left: 13, size: "size-7 sm:size-9", dur: 9, delay: 3.5},
    %{top: 28, right: 14, size: "size-7 sm:size-10", dur: 8, delay: 2.2},
    %{top: 36, left: 3, size: "size-9 sm:size-12", dur: 9, delay: 2},
    %{top: 42, right: 4, size: "size-10 sm:size-14", dur: 11, delay: 0.5},
    %{top: 51, left: 16, size: "size-7 sm:size-9", dur: 10, delay: 1.8},
    %{top: 57, right: 12, size: "size-8 sm:size-11", dur: 11, delay: 0.8},
    %{top: 66, left: 7, size: "size-8 sm:size-10", dur: 7, delay: 3},
    %{top: 72, right: 5, size: "size-10 sm:size-15", dur: 12, delay: 1.5},
    %{top: 81, left: 18, size: "size-8 sm:size-11", dur: 8, delay: 1.2},
    %{top: 88, right: 15, size: "size-7 sm:size-10", dur: 9, delay: 2.8},
    %{top: 8, left: 24, size: "size-7 sm:size-9", dur: 10, delay: 2.6},
    %{top: 33, right: 24, size: "size-8 sm:size-10", dur: 9, delay: 1.1},
    %{top: 47, left: 27, size: "size-7 sm:size-9", dur: 12, delay: 3.2},
    %{top: 62, right: 27, size: "size-7 sm:size-10", dur: 8, delay: 0.4},
    %{top: 76, left: 30, size: "size-7 sm:size-9", dur: 11, delay: 2.4},
    %{top: 94, right: 30, size: "size-8 sm:size-11", dur: 10, delay: 1.7}
  ]

  @host_base_theme_settings %{
    "logo" => "/images/logo.png",
    "banner" => "/images/banner.png",
    "favicon" => "/favicon.ico"
  }

  @host_theme_css_path "/theme.css"

  @theme_translatable_top_keys ~w(title tagline description site_message)

  @theme_translatable_array_fields [
    {["footer", "sections"], "title"},
    {["footer", "sections", "links"], "label"},
    {["navigation", "primary_links"], "label"},
    {["navigation", "primary_links", "items"], "label"},
    {["navigation", "guest_links"], "label"},
    {["navigation", "guest_links", "items"], "label"},
    {["navigation", "authenticated_links"], "label"},
    {["navigation", "authenticated_links", "items"], "label"},
    {["navigation", "account_links"], "label"},
    {["navigation", "account_links", "items"], "label"}
  ]

  @doc false
  def icon_placements(icons) when is_list(icons) do
    unique_icons = Enum.uniq(icons)

    if unique_icons == [] do
      []
    else
      # One icon per slot: wrapping around would stack a second icon on an
      # already-occupied position, so extra icons are dropped instead.
      unique_icons
      |> Enum.take(length(@icon_slots))
      |> Enum.with_index()
      |> Enum.map(fn {icon, index} ->
        @icon_slots |> Enum.at(index) |> Map.put(:name, icon)
      end)
    end
  end

  @doc """
  Renders the application layout shell.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: nil, doc: "current request path for nav active state"

  attr :flush, :boolean,
    default: false,
    doc: "when true, render content edge-to-edge with no main wrapper, padding, or footer"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = prepare_app_assigns(assigns)
    HostLayoutShell.app(assigns)
  end

  @doc false
  def resolve_theme(locale \\ nil, assigned_theme \\ %{}) do
    host_theme_settings = host_theme_settings()
    theme = merge_assigned_theme(fetch_theme(locale), assigned_theme)
    missing? = Map.drop(theme, Map.keys(host_theme_settings)) == %{}

    theme
    |> Map.put("title", Map.get(theme, "title") || if(missing?, do: "MISSING_THEME"))
    |> Map.put(
      "tagline",
      Map.get(theme, "tagline") ||
        if(missing?, do: "Add host theme config or set GAMEND_CONTENT_THEME_CONFIG")
    )
    |> then(&Map.merge(host_theme_settings, &1))
    |> translate_theme(locale)
  end

  @doc false
  def home_banner_link do
    Application.get_env(:game_server_web, :home_banner_link)
  end

  @doc false
  def extra_hook_modules do
    :game_server_web
    |> Application.get_env(:extra_hook_modules, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn path -> GameServerWeb.SRI.versioned_path(path) || path end)
  end

  @doc false
  def current_locale do
    GameServerWeb.GettextSync.current_locale()
  end

  @doc false
  def translate(message) when is_binary(message) do
    Gettext.gettext(GameServerWeb.GettextSync.host_backend(), message)
  end

  def translate(message), do: message

  defp translate_theme(theme, locale) when is_map(theme) do
    backend = GameServerWeb.GettextSync.host_backend()
    locale = translation_locale(locale)

    Gettext.with_locale(backend, locale, fn ->
      theme
      |> translate_top_level_theme_fields()
      |> translate_nested_theme_fields()
    end)
  end

  defp translation_locale(locale) when is_binary(locale) do
    GameServerWeb.GettextSync.normalize_locale(locale) || current_locale()
  end

  defp translation_locale(_locale), do: current_locale()

  defp translate_top_level_theme_fields(theme) do
    Enum.reduce(@theme_translatable_top_keys, theme, fn key, acc ->
      translate_map_field(acc, key)
    end)
  end

  defp translate_nested_theme_fields(theme) do
    theme
    |> translate_presentation_pages()
    |> then(fn translated ->
      Enum.reduce(@theme_translatable_array_fields, translated, fn {path, field}, acc ->
        translate_list_field_at_path(acc, path, field)
      end)
    end)
  end

  defp translate_presentation_pages(theme) when is_map(theme) do
    case Map.get(theme, "pages") do
      pages when is_map(pages) ->
        translated_pages =
          Map.new(pages, fn
            {key, page} when is_map(page) -> {key, translate_presentation_page(page)}
            {key, page} -> {key, page}
          end)

        Map.put(theme, "pages", translated_pages)

      _ ->
        theme
    end
  end

  defp translate_presentation_pages(theme), do: theme

  defp translate_presentation_page(page) do
    page
    |> update_map_at_path(["hero"], fn hero ->
      hero
      |> translate_map_field("title")
      |> translate_map_field("text")
      |> update_map_at_path(["image"], &translate_map_field(&1, "alt"))
      |> translate_list_field_at_path(["buttons"], "label")
    end)
    |> translate_list_field_at_path(["sections"], "title")
    |> translate_list_field_at_path(["sections"], "text")
    |> translate_list_field_at_path(["sections", "buttons"], "label")
    |> update_list_at_path(["sections"], fn section ->
      update_map_at_path(section, ["image"], &translate_map_field(&1, "alt"))
    end)
  end

  defp update_list_at_path(map, [key], fun) when is_map(map) do
    case Map.get(map, key) do
      items when is_list(items) -> Map.put(map, key, Enum.map(items, fun))
      _ -> map
    end
  end

  defp update_list_at_path(map, [key | rest], fun) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> Map.put(map, key, update_list_at_path(value, rest, fun))
      _ -> map
    end
  end

  defp update_list_at_path(map, _path, _fun), do: map

  defp update_map_at_path(map, [key], fun) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> Map.put(map, key, fun.(value))
      _ -> map
    end
  end

  defp update_map_at_path(map, [key | rest], fun) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> Map.put(map, key, update_map_at_path(value, rest, fun))
      _ -> map
    end
  end

  defp translate_list_field_at_path(map, [key], field) when is_map(map) do
    case Map.get(map, key) do
      items when is_list(items) ->
        Map.put(map, key, Enum.map(items, &translate_map_field(&1, field)))

      _ ->
        map
    end
  end

  defp translate_list_field_at_path(map, [key | rest], field) when is_map(map) do
    case Map.get(map, key) do
      nested when is_list(nested) ->
        Map.put(map, key, Enum.map(nested, &translate_list_field_at_path(&1, rest, field)))

      nested when is_map(nested) ->
        Map.put(map, key, translate_list_field_at_path(nested, rest, field))

      _ ->
        map
    end
  end

  defp translate_list_field_at_path(map, _path, _field), do: map

  defp translate_map_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> Map.put(map, key, translate(value))
      _ -> map
    end
  end

  defp translate_map_field(value, _key), do: value

  defp prepare_app_assigns(assigns) do
    conn = Map.get(assigns, :conn)

    current_path =
      Map.get(assigns, :current_path) ||
        if(conn, do: conn.request_path, else: "/")

    current_query = if conn, do: conn.query_string, else: ""
    locale = current_locale()

    theme = resolve_theme(locale, Map.get(assigns, :theme, %{}))
    en_theme = resolve_theme("en")

    navigation = navigation_config(theme, en_theme)
    background_icons = theme_list(theme, en_theme, "background_icons")
    site_message_source = Map.get(en_theme, "site_message", "")

    site_message =
      case Map.get(theme, "site_message", "") do
        "" -> site_message_source
        message -> message
      end

    site_message_hash =
      if site_message_source != "" do
        :erlang.phash2(site_message_source) |> Integer.to_string()
      else
        ""
      end

    notif_unread_count =
      if assigns[:current_scope] do
        GameServer.Notifications.count_unread_notifications(assigns.current_scope.user_id)
      else
        0
      end

    assign(assigns,
      current_path: current_path,
      current_query: current_query,
      locale: locale,
      known_locales: @known_locales,
      theme: theme,
      navigation: navigation,
      footer: Map.get(theme, "footer", %{}),
      background_icons: background_icons,
      site_message: site_message,
      site_message_hash: site_message_hash,
      notif_unread_count: notif_unread_count
    )
  end

  defp host_theme_settings do
    Map.put(@host_base_theme_settings, "css", host_theme_css_path())
  end

  defp host_theme_css_path do
    host_static_app = Application.get_env(:game_server_web, :host_static_app, :game_server_web)
    host_static_dir = Application.app_dir(host_static_app, "priv/static")
    theme_css_rel = String.trim_leading(@host_theme_css_path, "/")

    if File.exists?(Path.join(host_static_dir, theme_css_rel)) do
      @host_theme_css_path
    end
  end

  defp fetch_theme(locale) do
    theme_mod = Application.get_env(:game_server_web, :theme_module, JSONConfig)

    _ = Code.ensure_loaded?(theme_mod)

    # No locale hunting here any more: the provider translates through gettext,
    # which already falls back es_ES -> es -> source string. This used to try
    # one config file per locale and walk that chain by hand.
    if is_binary(locale) and function_exported?(theme_mod, :get_theme, 1) do
      safe_get_theme_1(theme_mod, locale)
    else
      safe_get_theme_0(theme_mod)
    end
  rescue
    _ -> %{}
  end

  defp safe_get_theme_1(theme_mod, locale) do
    theme_mod.get_theme(locale) || %{}
  rescue
    _ -> %{}
  end

  defp safe_get_theme_0(theme_mod) do
    if function_exported?(theme_mod, :get_theme, 0), do: theme_mod.get_theme() || %{}, else: %{}
  rescue
    _ -> %{}
  end

  defp merge_assigned_theme(full_theme, assigned_theme) when is_map(assigned_theme) do
    Enum.reduce(assigned_theme, full_theme, fn
      {_key, nil}, acc -> acc
      {_key, ""}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp merge_assigned_theme(full_theme, _assigned_theme), do: full_theme

  defp navigation_config(provider_theme, en_theme) do
    provider_navigation = Map.get(provider_theme, "navigation") || %{}
    en_navigation = Map.get(en_theme, "navigation") || %{}

    %{
      "primary_links" =>
        navigation_links(
          provider_navigation,
          en_navigation,
          "primary_links",
          default_primary_nav_links()
        ),
      "guest_links" => navigation_links(provider_navigation, en_navigation, "guest_links"),
      "authenticated_links" =>
        navigation_links(provider_navigation, en_navigation, "authenticated_links"),
      "account_links" =>
        merge_default_navigation_links(
          navigation_links(provider_navigation, en_navigation, "account_links"),
          default_account_nav_links()
        )
    }
  end

  defp navigation_links(provider_navigation, en_navigation, key, default \\ []) do
    case Map.get(provider_navigation, key) do
      links when is_list(links) ->
        links

      _ ->
        case Map.get(en_navigation, key) do
          links when is_list(links) -> links
          _ -> default
        end
    end
  end

  defp theme_list(provider_theme, en_theme, key, default \\ []) do
    case Map.get(provider_theme, key) do
      links when is_list(links) ->
        links

      _ ->
        case Map.get(en_theme, key) do
          links when is_list(links) -> links
          _ -> default
        end
    end
  end

  defp default_primary_nav_links do
    [
      %{
        "label" => translate("Play"),
        "href" => "/play",
        "icon" => "hero-play-solid"
      },
      %{
        "label" => translate("Social"),
        "icon" => "hero-user-group-solid",
        "items" => [
          %{
            "label" => translate("Leaderboards"),
            "href" => "/leaderboards",
            "icon" => "hero-chart-bar-solid"
          },
          %{
            "label" => translate("Quests"),
            "href" => "/quests",
            "icon" => "hero-trophy-solid"
          },
          %{
            "label" => translate("Tournaments"),
            "href" => "/tournaments",
            "icon" => "hero-bolt-solid"
          },
          %{
            "label" => translate("Groups"),
            "href" => "/groups",
            "icon" => "hero-user-group-solid"
          }
        ]
      }
    ]
  end

  defp default_account_nav_links do
    [
      %{
        "label" => translate("Admin"),
        "href" => "/admin",
        "icon" => "hero-cog-6-tooth-solid",
        "auth" => "admin"
      }
    ]
  end

  defp merge_default_navigation_links(configured, defaults)
       when is_list(configured) and is_list(defaults) do
    defaults
    |> Enum.reduce(Enum.reverse(configured), fn default, acc ->
      if navigation_entry_href?(acc, default["href"]) do
        acc
      else
        [default | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp merge_default_navigation_links(_configured, defaults), do: defaults

  defp navigation_entry_href?(entries, href) when is_list(entries) and is_binary(href) do
    Enum.any?(entries, fn
      %{"href" => ^href} -> true
      %{"items" => items} when is_list(items) -> navigation_entry_href?(items, href)
      _ -> false
    end)
  end

  def locale_labels, do: @locale_labels

  def strip_locale_prefix(path, known_locales) when is_binary(path) do
    segments = String.split(path, "/", trim: true)

    case segments do
      [first | rest] when is_list(rest) ->
        if first in known_locales do
          case rest do
            [] -> "/"
            _ -> "/" <> Enum.join(rest, "/")
          end
        else
          if String.starts_with?(path, "/"), do: path, else: "/"
        end

      _ ->
        if String.starts_with?(path, "/"), do: path, else: "/"
    end
  end

  def strip_locale_prefix(_, _known_locales), do: "/"

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={translate("Loading...")}
        phx-disconnected={JS.dispatch("gs:lv-disconnected")}
        phx-connected={JS.dispatch("gs:lv-connected")}
        phx-hook="ReconnectNotice"
        data-delay-ms="5000"
        hidden
      >
        {translate("Loading...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={translate("Loading...")}
        phx-disconnected={JS.dispatch("gs:lv-disconnected")}
        phx-connected={JS.dispatch("gs:lv-connected")}
        phx-hook="ReconnectNotice"
        data-delay-ms="5000"
        hidden
      >
        {translate("Loading...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/2 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=dark]_&]:left-1/2 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
