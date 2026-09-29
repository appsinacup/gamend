defmodule GamendWeb.HostLayouts do
  @moduledoc """
  Host-owned layout entrypoints and shared layout helpers.
  """

  use GamendWeb, :html

  alias Gamend.Theme.JSONConfig
  alias GamendWeb.HostLayoutShell
  alias GamendWeb.Plugs.LocalePath

  @known_locales GamendWeb.GettextSync.known_locales()

  @locale_labels %{
    "ar" => "العربية",
    "bg" => "Български",
    "cs" => "Čeština",
    "da" => "Dansk",
    "de" => "Deutsch",
    "el" => "Ελληνικά",
    "en" => "English",
    "es" => "Español",
    "fi" => "Suomi",
    "fr" => "Français",
    "hu" => "Magyar",
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

  @theme_translatable_top_keys ~w(title tagline description)

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

  attr :wide, :boolean,
    default: false,
    doc: "when true, the content column widens for a page with its own side columns"

  attr :background_icons, :any,
    default: nil,
    doc:
      "pass `false` when the page paints its own decorative icon layer, as `GamendWeb.PresentationPage` does — otherwise the shell adds a second one on top"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = prepare_app_assigns(assigns)
    HostLayoutShell.app(assigns)
  end

  @doc false
  def resolve_theme(locale \\ nil, assigned_theme \\ %{})

  # Memoised for the case that carries the traffic: no per-request theme
  # overlay, so the answer depends on the locale and nothing else.
  #
  # A page calls this three or four times -- once in `LoadTheme`, twice in
  # `prepare_app_assigns/1` (the viewer's locale and the English fallback the
  # navigation reads through), once more in `PageController` -- and each call
  # was running `translate_theme/2`, which walks the whole config including
  # every presentation page and translates each string. That was the single
  # largest cost left in a response, on every page of the site, and every
  # repetition of it produced the map the call before it had just produced.
  #
  # Keyed on the locale, which the `Locale` plug validates against
  # `known_locales/0` before it ever reaches gettext, so the entry count is the
  # locale list and not something a URL can inflate. The value carries a
  # fingerprint of everything the output is built from, so an edited theme or a
  # newly deployed `theme.css` is picked up on the next read rather than
  # surviving until restart.
  #
  # An overlay is not cached at all rather than folded into the key: a host
  # that varies the theme per request would otherwise write a new entry per
  # request, and `:persistent_term.put/2` scans every process on the node.
  # Rendering it uncached is far cheaper than that.
  def resolve_theme(locale, assigned_theme) when map_size(assigned_theme) == 0 do
    base = fetch_theme(locale)
    settings = host_theme_settings()
    fingerprint = :erlang.phash2({base, settings})
    key = {__MODULE__, :resolved_theme, resolved_theme_locale(locale)}

    case :persistent_term.get(key, :miss) do
      {^fingerprint, theme} ->
        theme

      _ ->
        theme = build_theme(base, settings, assigned_theme, locale)
        :persistent_term.put(key, {fingerprint, theme})
        theme
    end
  end

  def resolve_theme(locale, assigned_theme) do
    build_theme(fetch_theme(locale), host_theme_settings(), assigned_theme, locale)
  end

  # `translate_theme/2` falls back to the process locale when it is not handed
  # a usable one, so `nil` and an unknown string both mean "whatever this
  # process is set to" -- and keying either of those literally would file two
  # locales under one entry.
  defp resolved_theme_locale(locale) do
    (is_binary(locale) && GamendWeb.GettextSync.normalize_locale(locale)) || current_locale()
  end

  defp build_theme(base, host_theme_settings, assigned_theme, locale) do
    theme = merge_assigned_theme(base, assigned_theme)
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
    Application.get_env(:gamend_web, :home_banner_link)
  end

  @doc false
  def extra_hook_modules do
    :gamend_web
    |> Application.get_env(:extra_hook_modules, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn path -> GamendWeb.SRI.versioned_path(path) || path end)
  end

  @doc """
  Encodes a schema.org object for an `application/ld+json` script tag.

  `nil` values are dropped so callers can build objects with optional fields
  without emitting `null`, which validators flag. `<` is escaped because a
  `</script>` inside a string would otherwise close the tag early — the one
  way JSON-LD turns into an injection vector.
  """
  @spec json_ld(map()) :: String.t()
  def json_ld(object) do
    object
    |> drop_nils()
    |> Jason.encode!()
    |> String.replace("<", "\\u003C")
  end

  defp drop_nils(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {key, drop_nils(value)} end)
  end

  defp drop_nils(list) when is_list(list), do: Enum.map(list, &drop_nils/1)
  defp drop_nils(other), do: other

  @doc false
  def current_locale do
    GamendWeb.GettextSync.current_locale()
  end

  @doc false
  def translate(message) when is_binary(message) do
    Gettext.gettext(GamendWeb.GettextSync.host_backend(), message)
  end

  def translate(message), do: message

  defp translate_theme(theme, locale) when is_map(theme) do
    backend = GamendWeb.GettextSync.host_backend()
    locale = translation_locale(locale)

    Gettext.with_locale(backend, locale, fn ->
      theme
      |> translate_top_level_theme_fields()
      |> translate_nested_theme_fields()
    end)
  end

  defp translation_locale(locale) when is_binary(locale) do
    GamendWeb.GettextSync.normalize_locale(locale) || current_locale()
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
    |> translate_list_field_at_path(["sections", "links"], "label")
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

  # What the shell renders from, all of it derived. A function component is
  # stateless, so the derivation runs again on every render and `assign/3`
  # marks each key changed — assigns never already hold the value to compare
  # against. Unchecked, that re-renders the navbar, the language picker, the
  # breadcrumbs and the footer on *every* diff any LiveView on the site sends.
  # The client then morphs that markup back over the DOM, and an open
  # `<details>` dropdown has no `open` attribute in it, so the menu shuts
  # itself. The Tests page refreshes its clock once a second, which turned that
  # into a menu closing a second after it was opened.
  @derived_shell_assigns [
    :background_icons,
    :breadcrumbs,
    :current_path,
    :current_query,
    :footer,
    :known_locales,
    :locale,
    :navigation,
    :notif_unread_count,
    :search,
    :theme
  ]

  # The attrs the derivation reads. Nothing else it depends on can move inside
  # the life of one render: the locale belongs to the process, the theme config
  # is global and only re-read on deploy, and `:current_path` is kept in step
  # by the `:set_current_path` hook in `GamendWeb.UserAuth`, so a `push_patch`
  # to another URL does change the nav highlight.
  @shell_assign_inputs [
    :background_icons,
    :conn,
    :current_path,
    :current_scope,
    :flush,
    :theme,
    :wide
  ]

  # The assigns `HostLayoutShell.app/1` renders from, derived from the handful
  # of attrs `app/1` takes. Public so the change-tracking contract above can be
  # asserted directly: what comes back out of `__changed__` is the whole of the
  # fix, and it leaves no trace in rendered markup.
  @doc false
  def prepare_app_assigns(assigns) do
    rerender? = shell_inputs_changed?(assigns)
    conn = Map.get(assigns, :conn)

    # `Layouts.app` is a function component, so it only sees the attrs a
    # template hands it — several core templates pass neither `current_path`
    # nor `conn`, and defaulting those to "/" made the nav highlight Home on
    # every one of them. The path the PageMeta plug stashed is the reliable
    # last resort.
    current_path =
      Map.get(assigns, :current_path) ||
        if(conn, do: conn.request_path, else: nil) ||
        Process.get(:gamend_page_path) ||
        "/"

    current_query = if conn, do: conn.query_string, else: ""
    locale = current_locale()

    theme = resolve_theme(locale, Map.get(assigns, :theme, %{}))
    en_theme = resolve_theme("en")

    navigation = navigation_config(theme, en_theme)
    background_icons = shell_background_icons(assigns, theme, en_theme)

    notif_unread_count = unread_notifications(assigns, rerender?)

    assigns =
      assign(assigns,
        current_path: current_path,
        current_query: current_query,
        locale: locale,
        known_locales: @known_locales,
        theme: theme,
        navigation: localize_hrefs(navigation, locale),
        footer: localize_hrefs(Map.get(theme, "footer", %{}), locale),
        background_icons: background_icons,
        notif_unread_count: notif_unread_count,
        search: search_assign(locale),
        breadcrumbs: breadcrumbs_for(current_path, locale)
      )

    freeze_derived_shell_assigns(assigns, rerender?)
  end

  # The index URL carries the locale, so this moves when the locale does —
  # which is why `:search` is one of the frozen shell assigns rather than a
  # constant computed once.
  defp search_assign(locale) do
    if GamendWeb.SearchIndex.enabled?() do
      %{
        enabled: true,
        index_url: GamendWeb.SearchIndex.index_path(locale),
        # Absent unless the host answers live queries, which is what tells the
        # palette whether there is anything to ask for per keystroke.
        query_url: if(GamendWeb.SearchIndex.live?(), do: GamendWeb.SearchIndex.query_path(locale))
      }
    else
      %{enabled: false, index_url: nil, query_url: nil}
    end
  end

  # `nil` means the caller is not change-tracking at all — a dead render, or a
  # first render, where every dynamic has to be produced.
  defp shell_inputs_changed?(%{__changed__: changed}) when is_map(changed),
    do: Enum.any?(@shell_assign_inputs, &Map.has_key?(changed, &1))

  defp shell_inputs_changed?(_assigns), do: true

  defp freeze_derived_shell_assigns(assigns, true), do: assigns

  defp freeze_derived_shell_assigns(%{__changed__: changed} = assigns, false)
       when is_map(changed),
       do: %{assigns | __changed__: Map.drop(changed, @derived_shell_assigns)}

  defp freeze_derived_shell_assigns(assigns, false), do: assigns

  # The unread count is the one derived value that can move without an attr
  # moving, and a function component has nowhere to keep the last one it
  # rendered. The process does: a LiveView is one process for the life of the
  # page, so a render that is not re-rendering the navbar reuses the number the
  # navbar is already showing instead of asking the database for it again. A
  # dead render is a fresh process, so it always counts.
  defp unread_notifications(assigns, true) do
    count =
      if scope = assigns[:current_scope] do
        Gamend.Notifications.count_unread_notifications(scope.user_id)
      else
        0
      end

    Process.put(:gamend_notif_unread_count, count)
    count
  end

  defp unread_notifications(_assigns, false), do: Process.get(:gamend_notif_unread_count, 0)

  # The shell's icon layer is the fallback for pages that do not paint one
  # themselves. A `PresentationPage` draws its own, band by band, and says so
  # with `background_icons={false}` — without that, the shell's fixed layer
  # went on top of it and every icon showed up twice, a few pixels apart. The
  # flush layout is the fullscreen game: no decoration there either.
  defp shell_background_icons(assigns, theme, en_theme) do
    if Map.get(assigns, :background_icons) == false or Map.get(assigns, :flush) == true do
      []
    else
      theme_list(theme, en_theme, "background_icons")
    end
  end

  # Derived here rather than threaded through as an assign: `Layouts.app` is a
  # function component, so it only ever sees the attrs a template passes it —
  # a conn assign set by the PageMeta plug would never arrive. Deriving from
  # `current_path` means every page gets a trail without touching a single
  # template, LiveViews included.
  defp breadcrumbs_for(current_path, locale) do
    case Application.get_env(:gamend_web, :page_meta_provider) do
      nil ->
        []

      module ->
        if Code.ensure_loaded?(module) and function_exported?(module, :breadcrumbs, 1) do
          current_path
          |> breadcrumb_path()
          |> module.breadcrumbs()
          |> Enum.map(fn {label, path} -> {label, localized_href(path, locale)} end)
        else
          []
        end
    end
  end

  # The plug's path is authoritative: it is already locale-stripped, and it is
  # present even when a template passed no `current_path` at all.
  defp breadcrumb_path(current_path) do
    case Process.get(:gamend_page_path) do
      path when is_binary(path) -> path
      _ when is_binary(current_path) -> strip_locale_prefix(current_path, @known_locales)
      _ -> "/"
    end
  end

  defp host_theme_settings do
    Map.put(@host_base_theme_settings, "css", host_theme_css_path())
  end

  # Resolved once. This asks the code server where an app lives and then stats a
  # file, and `resolve_theme/2` calls it three or four times per page -- a
  # filesystem syscall on the render path of every request on the site, to
  # answer a question whose answer is fixed the moment the release is built.
  # File IO also crosses onto a dirty scheduler, so the cost under load is
  # worse than the ~8us it measures on an idle box.
  #
  # The consequence is that dropping a `theme.css` into a running release, or
  # into a project's static overlay, is not picked up until the static files
  # are reloaded (`GamendWeb.ProjectStatic.reload/0`, on a theme reload) or the
  # node restarts, which is the rule the rest of the static pipeline follows.
  defp host_theme_css_path do
    key = {__MODULE__, :host_theme_css_path}
    generation = GamendWeb.ProjectStatic.generation()

    case :persistent_term.get(key, :miss) do
      {^generation, path} ->
        path

      _ ->
        path = compute_host_theme_css_path()
        :persistent_term.put(key, {generation, path})
        path
    end
  end

  # Through the resolver, so a project's own `theme.css` in its static overlay
  # counts as well as the host app's.
  defp compute_host_theme_css_path do
    if GamendWeb.ProjectStatic.path_for(@host_theme_css_path) do
      @host_theme_css_path
    end
  end

  defp fetch_theme(locale) do
    theme_mod = Application.get_env(:gamend_web, :theme_module, JSONConfig)

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

  @doc """
  The four navigation sections for a locale, as configured.

  The same map the navbar renders from, for callers that are not the navbar —
  the search palette flattens it into rows. Hrefs are left clean: this is the
  configured shape, not a rendering of it, and a caller that needs locale
  prefixes runs `localized_href/2` itself.
  """
  @spec navigation(String.t() | nil) :: map()
  def navigation(locale \\ nil) do
    navigation_config(resolve_theme(locale), resolve_theme("en"))
  end

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

  @doc """
  Rewrites an internal path so it keeps the reader's locale prefix.

  Without this the prefix survives exactly one click: `/fr/about` renders in
  French, but every link out of it points at a clean path, so the next page is
  back at `/play` — French only because the session says so. That URL is then
  wrong in the two places it matters, sharing it hands the recipient English,
  and it is the English URL that gets bookmarked and linked to.

  Leaves alone: the default locale (its pages *are* the clean URLs), external
  and protocol-relative hrefs, and any path `LocalePath` does not serve under a
  prefix — pointing at `/fr/blog/some-post` when that only redirects would just
  spend a redirect per link.
  """
  @spec localized_href(term(), String.t() | nil) :: term()
  def localized_href(href, locale) when is_binary(href) and is_binary(locale) do
    prefix = LocalePath.url_locale(locale)

    cond do
      locale == LocalePath.default_locale() -> href
      not String.starts_with?(href, "/") -> href
      String.starts_with?(href, "//") -> href
      true -> prefix_path(href, prefix)
    end
  end

  def localized_href(href, _locale), do: href

  defp prefix_path(href, prefix) do
    {path, suffix} =
      case :binary.match(href, ["?", "#"]) do
        {at, _len} -> String.split_at(href, at)
        :nomatch -> {href, ""}
      end

    cond do
      not LocalePath.localized_path?(path) -> href
      path == "/" -> "/" <> prefix <> suffix
      true -> "/" <> prefix <> path <> suffix
    end
  end

  @doc """
  Deep-rewrites every `"href"` in a theme fragment through `localized_href/2`.

  The nav, footer and presentation-page sections are all plain config maps, so
  one walk covers every configured link rather than one edit per template.
  """
  @spec localize_hrefs(term(), String.t() | nil) :: term()
  def localize_hrefs(map, locale) when is_map(map) and not is_struct(map) do
    Map.new(map, fn
      {"href", href} -> {"href", localized_href(href, locale)}
      {key, value} -> {key, localize_hrefs(value, locale)}
    end)
  end

  def localize_hrefs(list, locale) when is_list(list),
    do: Enum.map(list, &localize_hrefs(&1, locale))

  def localize_hrefs(other, _locale), do: other

  def strip_locale_prefix(path, known_locales) when is_binary(path) do
    segments = String.split(path, "/", trim: true)

    case segments do
      [first | rest] when is_list(rest) ->
        if first in known_locales or GamendWeb.GettextSync.normalize_locale(first) do
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

      <%!-- Shown by CSS while <html data-connection="offline"> is set, which
            `startConnectionState` in app.js does 5 s into a drop and clears on
            reconnect. No `hidden` toggle and no dismiss button: the next DOM
            patch would undo the one, and the other would hide a notice that
            is still true. --%>
      <div
        id="connection-notice"
        role="status"
        class="toast toast-top toast-center z-50 hidden [html[data-connection=offline]_&]:flex"
      >
        <div class="alert alert-warning">
          <.icon name="hero-signal-slash" class="size-5 shrink-0" />
          <span>{translate("You're offline. Trying to reconnect...")}</span>
          <.icon name="hero-arrow-path" class="size-4 shrink-0 motion-safe:animate-spin" />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/2 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 start-0 [[data-theme=dark]_&]:start-1/2 transition-[inset-inline-start]" />

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={translate("Switch to light theme")}
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={translate("Switch to dark theme")}
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
