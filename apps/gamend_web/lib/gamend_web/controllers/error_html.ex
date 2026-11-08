defmodule GamendWeb.ErrorHTML do
  @moduledoc """
  Error pages for HTML requests.

  Phoenix's default renders the status message as plain text — a 404 was nine
  bytes reading "Not Found", which looks like the whole site is broken rather
  than one URL being wrong, and gives a reader nowhere to go but Back.

  `render_errors` is configured `layout: false`, so these templates are whole
  documents. That is the right shape for them anyway: this page has to render
  when something has already failed, so it depends on no layout, no asset
  bundle and no assign the endpoint might not have set. Styling is inline —
  the browser CSP permits inline styles but not inline scripts, so there is
  also no JS.

  Locale-aware where it can be: the `LocalePath` plug has usually already run
  and set the gettext locale, so the copy is translated and the links keep the
  reader's language prefix. Where it has not (an error early in the pipeline),
  it falls back to the default locale rather than raising — the one thing an
  error page must never do is fail.
  """
  use GamendWeb, :html

  alias GamendWeb.Plugs.LocalePath

  require GamendWeb.ColorScheme, as: ColorScheme

  embed_templates "error_html/*"

  @doc """
  Renders an error page for a status template such as `"404.html"`.

  Anything without copy of its own falls through to the generic page rather
  than to Phoenix's plain-text default, so no status can render as a bare
  string.
  """
  def render(template, assigns) do
    status = status_code(template)

    error_page(
      Map.merge(assigns, %{
        status: status,
        title: title_for(status),
        message: message_for(status),
        locale: locale(assigns),
        color_mode: color_mode(assigns),
        home_path: home_path(assigns),
        links: links(assigns),
        theme_css: theme_css(assigns)
      })
    )
  end

  @doc """
  Extra places to send a lost reader, beyond Home.

  Core has no idea what a given host's pages are called — `/vocabulary` means
  nothing to a Gamend server that is not this one — so the list is empty by
  default and each host names its own:

      config :gamend_web, :error_page_links, [
        %{label: "Vocabulary", path: "vocabulary"},
        %{label: "Play", path: "play"}
      ]

  `path` is relative and gets the reader's locale prefix, so from `/fr/nope`
  the links stay French. Labels are looked up in the HOST's gettext catalogue
  (`:host_gettext_backend`) in the reader's locale at render time; they
  resolve when the msgid already exists there (these are navigation labels,
  so it generally does) and fall back to the literal otherwise.

  An `:error_page_links` assign wins over the application env, so a caller (or
  a test) can pin the list for one render without touching global config.
  """
  def links(assigns \\ %{}) do
    locale = locale(assigns)

    assigns
    |> configured_links()
    |> Enum.filter(&valid_link?/1)
    |> Enum.map(&%{label: translate(&1.label, locale), path: String.trim_leading(&1.path, "/")})
  end

  defp configured_links(%{error_page_links: links}) when is_list(links), do: links
  defp configured_links(_assigns), do: Application.get_env(:gamend_web, :error_page_links, [])

  defp valid_link?(%{label: label, path: path}) when is_binary(label) and is_binary(path),
    do: label != "" and path != ""

  defp valid_link?(_link), do: false

  # Runtime lookup: gettext cannot extract a non-literal, but these msgids are
  # already in the host's catalogue from the navigation that uses them. The
  # HOST's backend: the labels are its navigation, and core's own catalogue
  # holds none of them, so looking there left them English in every locale.
  # An error page must never fail, so any trouble here keeps the literal.
  defp translate(label, locale) do
    backend = GamendWeb.GettextSync.host_backend()
    Gettext.with_locale(backend, locale, fn -> Gettext.dgettext(backend, "default", label) end)
  rescue
    _ -> label
  catch
    _, _ -> label
  end

  defp status_code(template) do
    template
    |> Path.rootname()
    |> Integer.parse()
    |> case do
      {status, _rest} -> status
      :error -> 500
    end
  end

  defp title_for(404), do: gettext("Page not found")
  defp title_for(403), do: gettext("Not allowed")
  defp title_for(429), do: gettext("Too many requests")
  defp title_for(_status), do: gettext("Something went wrong")

  defp message_for(404) do
    gettext(
      "The page you were looking for has moved or never existed. The rest of the site is fine."
    )
  end

  defp message_for(403) do
    gettext("You do not have access to this page. Signing in may help.")
  end

  defp message_for(429) do
    gettext(
      "You have made a lot of requests in a short time. Please wait a moment and try again."
    )
  end

  defp message_for(413) do
    gettext("That was too large to send. Try a smaller file.")
  end

  # A 4xx is the request, not the server: "something broke on our side" would
  # be wrong, and telling the reader it was logged would be too.
  defp message_for(status) when status in 400..499 do
    gettext("The request could not be handled. Go back and try again.")
  end

  defp message_for(_status) do
    gettext("Something broke on our side. It has been logged, and the rest of the site is fine.")
  end

  # The conn is present for a normal request but absent when the error is
  # rendered outside one, so both shapes have to work.
  defp locale(%{conn: %Plug.Conn{assigns: %{locale: locale}}}) when is_binary(locale), do: locale
  defp locale(_assigns), do: LocalePath.default_locale()

  # Same theme as the rest of the site when the pipeline got far enough to
  # resolve one; daisyUI's light theme otherwise, which is what the root layout
  # falls back to as well.
  defp color_mode(%{conn: %Plug.Conn{assigns: %{color_mode: mode}}}) when is_binary(mode),
    do: mode

  defp color_mode(%{color_mode: mode}) when is_binary(mode), do: mode
  defp color_mode(_assigns), do: ColorScheme.light()

  # The host theme's stylesheet, which is where the brand palette lives —
  # app.css alone is daisyUI's defaults. Resolving a theme touches host config,
  # so a failure here falls back to no theme sheet rather than turning a 404
  # into a 500.
  defp theme_css(assigns) do
    theme =
      GamendWeb.Layouts.resolve_theme(
        locale(assigns),
        get_in(assigns, [:conn, Access.key(:assigns), :theme]) || %{}
      )

    case Map.get(theme, "css") do
      css when is_binary(css) and css != "" -> css
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  # Keep the reader in their language: from `/fr/nope` the links should point at
  # `/fr/...`, not drop them into English. Always ends with a slash so callers
  # can append a path segment.
  defp home_path(assigns) do
    locale = locale(assigns)

    if locale == LocalePath.default_locale() do
      "/"
    else
      "/" <> LocalePath.url_locale(locale) <> "/"
    end
  end
end
