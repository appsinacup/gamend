defmodule GameServerWeb.PresentationPage do
  @moduledoc """
  Shared hero-and-sections page renderer for host presentation pages.
  """

  use GameServerWeb, :html

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

  attr :page, :map, required: true
  attr :background_icons, :list, default: []
  attr :full_bleed_hero, :boolean, default: true

  def page(assigns) do
    sections = sections_with_page_defaults(assigns.page)

    assigns =
      assign(assigns,
        hero: Map.get(assigns.page, "hero", %{}),
        sections: sections,
        background_icon_bands: background_icon_bands(sections)
      )

    ~H"""
    <div class={
      if(@full_bleed_hero, do: "relative w-screen left-1/2 -translate-x-1/2 -mt-20", else: "")
    }>
      <div class="relative overflow-hidden">
        <.background_icons icons={@background_icons} bands={@background_icon_bands} />
        <section class="relative min-h-screen">
          <div class="relative z-10 flex min-h-screen items-center px-6 pb-12 pt-24 sm:px-8 lg:px-12">
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
                <div class="max-w-2xl text-base leading-relaxed text-base-content/75 sm:text-lg lg:text-xl">
                  {rich_text(Map.get(@hero, "text", ""))}
                </div>
                <.buttons buttons={Map.get(@hero, "buttons", [])} />
              </div>
            </div>
          </div>
          <a
            :if={@sections != []}
            href="#more-content"
            aria-label="Scroll to content"
            class="absolute bottom-6 left-1/2 z-20 -translate-x-1/2 text-base-content/55 transition hover:text-base-content motion-safe:animate-bounce"
          >
            <.dynamic_icon name="hero-chevron-down-solid" class="size-9" />
          </a>
        </section>

        <div id="more-content" class="scroll-mt-20"></div>

        <div
          :if={@sections != []}
          class={[
            "relative z-10 mx-auto grid w-full gap-y-4 px-4 sm:px-6 lg:px-8",
            content_width_class()
          ]}
        >
          <%= for section <- @sections do %>
            <.section section={section} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :icons, :list, default: []
  attr :bands, :integer, default: 1

  def background_icons(assigns) do
    icons = if is_list(assigns.icons), do: assigns.icons, else: []
    bands = max(assigns.bands, 1)

    assigns =
      assign(assigns,
        placements: GameServerWeb.Layouts.icon_placements(icons),
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

  def buttons(assigns) do
    buttons = if is_list(assigns.buttons), do: assigns.buttons, else: []
    assigns = assign(assigns, buttons: Enum.filter(buttons, &valid_button?/1))

    ~H"""
    <div
      :if={@buttons != []}
      class="flex w-full flex-col items-center justify-center gap-3 sm:flex-row sm:flex-wrap"
    >
      <a
        :for={button <- @buttons}
        href={button["href"]}
        target={if button["external"], do: "_blank"}
        rel={if button["external"], do: "noopener noreferrer"}
        class={button_class(button)}
      >
        <.dynamic_icon
          :if={button["icon"]}
          name={button["icon"]}
          class="size-5 shrink-0 text-current"
        />
        <span class="truncate">{Map.get(button, "label", "")}</span>
      </a>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :variant, :string, default: "section"

  def media(assigns) do
    image = image_config(assigns.item)

    assigns =
      assign(assigns,
        image: image,
        icon: Map.get(assigns.item, "icon"),
        size: media_size(assigns.item, assigns.variant)
      )

    ~H"""
    <div class="flex w-full items-center justify-center">
      <div class={media_shell_class()}>
        <.media_visual image={@image} icon={@icon} variant={@variant} size={@size} />
      </div>
    </div>
    """
  end

  attr :image, :map, default: %{}
  attr :icon, :string, default: nil
  attr :variant, :string, default: "section"
  attr :size, :string, default: "section"

  def media_visual(assigns) do
    ~H"""
    <img
      :if={@image.light && !@image.dark}
      src={@image.light}
      alt={@image.alt}
      width={@image.width}
      height={@image.height}
      loading={if(@variant == "hero", do: "eager", else: "lazy")}
      fetchpriority={if(@variant == "hero", do: "high", else: nil)}
      decoding="async"
      class={media_class(@size)}
    />
    <div :if={@image.light && @image.dark} class="contents">
      <img
        src={@image.light}
        alt={@image.alt}
        width={@image.width}
        height={@image.height}
        loading={if(@variant == "hero", do: "eager", else: "lazy")}
        fetchpriority={if(@variant == "hero", do: "high", else: nil)}
        decoding="async"
        class={[media_class(@size), "[[data-theme=dark]_&]:hidden"]}
      />
      <img
        src={@image.dark}
        alt={@image.alt}
        width={@image.width}
        height={@image.height}
        loading={if(@variant == "hero", do: "eager", else: "lazy")}
        fetchpriority={if(@variant == "hero", do: "high", else: nil)}
        decoding="async"
        class={[media_class(@size), "hidden [[data-theme=dark]_&]:block"]}
      />
    </div>
    <div
      :if={!@image.light && @icon}
      class="grid aspect-square w-full max-w-48 place-items-center rounded-lg bg-base-100/70 text-base-content/70 shadow-sm"
    >
      <.dynamic_icon name={@icon} class="size-16" />
    </div>
    """
  end

  attr :section, :map, required: true

  def section(assigns) do
    ~H"""
    <section class={[
      "grid w-full gap-6 md:gap-x-8 md:gap-y-4",
      "items-center",
      section_height_class(@section),
      grid_class(@section, "section")
    ]}>
      <div class={["flex items-center", media_order_class(@section)]}>
        <.media item={@section} variant="section" />
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
        <div class="text-base leading-relaxed text-base-content/75">
          {rich_text(Map.get(@section, "text", ""))}
        </div>
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

  defp section_height_class(section) do
    case section_height(section) do
      value when value in ["compact", "sm", "small"] ->
        "py-8"

      value when value in ["half", "50", "50%"] ->
        "min-h-[calc(50dvh-2.5rem)] py-8"

      value when value in ["full", "screen", "100", "100%"] ->
        "min-h-[calc(100dvh-5rem)] py-12"

      _ ->
        "py-8"
    end
  end

  defp section_height(section), do: Map.get(section, "height", "compact")

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
      "left" -> "text-left items-start"
      "right" -> "text-right items-end"
      _ -> "text-center items-center"
    end
  end

  defp image_config(item) do
    case Map.get(item, "image") do
      image when is_map(image) ->
        light = non_empty_string(Map.get(image, "light"))
        dark = non_empty_string(Map.get(image, "dark"))
        {natural_width, natural_height} = image_dimensions(light || dark)

        %{
          light: image_src(light),
          dark: image_src(dark),
          alt: Map.get(image, "alt", ""),
          width: positive_int(Map.get(image, "width")) || natural_width,
          height: positive_int(Map.get(image, "height")) || natural_height
        }

      _ ->
        %{light: nil, dark: nil, alt: "", width: nil, height: nil}
    end
  end

  defp section_text_frame_class(section) do
    if image_config(section).light do
      "md:min-h-[min(42dvh,24rem)]"
    else
      "md:min-h-48"
    end
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
    path = non_empty_string(path)

    cond do
      is_nil(path) ->
        nil

      generated = generated_image_path(path) ->
        if GameServerWeb.SRI.integrity(generated) do
          GameServerWeb.SRI.versioned_path(generated) || generated
        else
          GameServerWeb.SRI.versioned_path(path) || path
        end

      true ->
        GameServerWeb.SRI.versioned_path(path) || path
    end
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

  defp image_dimensions(path) do
    path = non_empty_string(path)
    clean_path = path && (URI.parse(path).path || path)

    with clean when is_binary(clean) <- clean_path,
         file_path when is_binary(file_path) <- static_file_path(clean) do
      read_image_dimensions(file_path)
    else
      _ -> {nil, nil}
    end
  end

  defp static_file_path(clean_path) do
    [
      Application.get_env(:game_server_web, :asset_static_app, :game_server_web),
      Application.get_env(:game_server_web, :host_static_app, :game_server_web),
      :game_server_web
    ]
    |> Enum.uniq()
    |> Enum.map(&app_static_dir/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn static_dir ->
      file_path = Path.join(static_dir, String.trim_leading(clean_path, "/"))
      if File.exists?(file_path), do: file_path
    end)
  end

  defp app_static_dir(app) when is_atom(app) do
    if Application.spec(app, :vsn) do
      Application.app_dir(app, "priv/static")
    end
  end

  defp app_static_dir(_app), do: nil

  defp read_image_dimensions(file_path) do
    case File.read(file_path) do
      {:ok,
       <<0x89, "PNG\r\n", 0x1A, "\n", _length::32, "IHDR", width::32, height::32, _::binary>>} ->
        {width, height}

      _ ->
        {nil, nil}
    end
  end

  defp media_width(item, "hero"), do: Map.get(item, "media_width", "half")
  defp media_width(item, _variant), do: Map.get(item, "media_width", "third")

  defp media_size(item, variant) do
    case Map.get(item, "media_size", variant) do
      value when value in ["hero", "section"] -> value
      _ -> variant
    end
  end

  defp desktop_image_position(item), do: Map.get(item, "image_position_desktop", "left")

  defp media_class("hero"), do: "block max-h-[58dvh] w-full rounded-lg object-contain"

  defp media_class("section"),
    do: "block aspect-square max-h-[42dvh] w-full rounded-lg object-contain"

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
