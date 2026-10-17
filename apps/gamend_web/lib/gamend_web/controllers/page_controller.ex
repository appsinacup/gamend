defmodule GamendWeb.PageController do
  use GamendWeb, :controller

  alias GamendWeb.PresentationPage

  def home(conn, _params) do
    render_presentation_page(conn, "/", gettext("Home"))
  end

  # A markdown page from the `:pages` collection, when the host registered one
  # — `content/pages/faq.md` answering `/faq` with nothing routed — else a
  # theme page from the JSON. A host without the collection sees no change.
  def configured_page(conn, %{"path" => path}) do
    slug = Enum.join(path, "/")

    case Gamend.Content.get_doc(:pages, slug) do
      nil -> render_presentation_page(conn, "/" <> slug, gettext("Page"))
      page -> render_markdown_page(conn, page, slug)
    end
  end

  defp render_markdown_page(conn, page, slug) do
    conn
    |> assign(:page_title, page.title)
    |> assign(:page, page)
    |> assign(:html, Gamend.Content.doc_html(:pages, slug))
    |> assign(:wide, Map.get(page, :meta, %{})["layout"] == "wide")
    |> render(:markdown_page)
  end

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, gettext("Privacy"))
    |> assign_contact_email()
    |> render(:privacy)
  end

  def data_deletion(conn, _params) do
    conn
    |> assign(:page_title, gettext("Data deletion"))
    |> assign_contact_email()
    |> render(:data_deletion)
  end

  # The site's building blocks on one page, each captioned with the classes
  # that draw it, so a new screen copies them instead of inventing a look. A
  # reference rather than content, so not worth indexing.
  def ui(conn, _params) do
    conn
    |> assign(:page_title, gettext("UI elements"))
    |> assign(:robots, "noindex, follow")
    |> render(:ui)
  end

  def terms(conn, _params) do
    conn
    |> assign(:page_title, gettext("Terms"))
    |> assign_contact_email()
    |> render(:terms)
  end

  # The legal pages name an address when the theme gives one (`contact_email`).
  # Without it they fall back to "our support channels", which a store review or
  # a GDPR request cannot act on — so a host shipping these pages should set it.
  defp assign_contact_email(conn) do
    locale = Gettext.get_locale(GamendWeb.Gettext)
    theme = GamendWeb.Layouts.resolve_theme(locale, conn.assigns[:theme] || %{})
    assign(conn, :contact_email, contact_email(theme))
  end

  defp contact_email(theme) do
    with email when is_binary(email) <- Map.get(theme, "contact_email"),
         email = String.trim(email),
         true <- Regex.match?(~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/, email) do
      email
    else
      _ -> nil
    end
  end

  defp render_presentation_page(conn, path, fallback_title) do
    locale = Gettext.get_locale(GamendWeb.Gettext)
    theme = GamendWeb.Layouts.resolve_theme(locale, conn.assigns[:theme] || %{})

    case PresentationPage.page_for_path(theme, path) || missing_home_page(theme, path) do
      nil ->
        # Not `text("Not Found")`: this decides for itself that the request is a
        # 404, so it never reaches `render_errors` and the reader got nine bytes
        # of plain text while the error template sat unused.
        GamendWeb.ErrorResponse.not_found(conn)

      page ->
        # Hero and section buttons are config hrefs like "/play"; without this
        # every call to action on /fr drops the reader back to a clean URL.
        page = GamendWeb.HostLayouts.localize_hrefs(page, locale)

        # Rendered here rather than in the template so the memo has a key: the
        # body is a pure function of the theme page and the locale, and the
        # template does not know either.
        background_icons = Map.get(theme, "background_icons") || []

        conn
        |> assign(:page_title, PresentationPage.page_title(page, fallback_title))
        |> render(:presentation_page,
          presentation_body: presentation_body(conn, page, background_icons, locale, path),
          theme: theme
        )
    end
  end

  # A signed-in reader's page is rendered for them, so a host component on
  # it may draw their own things (the languages they opened last); a visitor
  # and a crawler get the body memoised per locale and path.
  defp presentation_body(conn, page, background_icons, locale, path) do
    scope = conn.assigns[:current_scope]

    if scope && Gamend.Accounts.Scope.user(scope),
      do: PresentationPage.personal_body(page, background_icons, scope),
      else: PresentationPage.cached_body(page, background_icons, locale, path)
  end

  defp missing_home_page(theme, "/") do
    %{
      "path" => "/",
      "hero" => %{
        "title" => Map.get(theme, "title", ""),
        "text" => Map.get(theme, "description", ""),
        "image" => %{
          "light" => Map.get(theme, "banner", "/images/banner.png"),
          "alt" => Map.get(theme, "title", "")
        }
      },
      "sections" => []
    }
  end

  defp missing_home_page(_theme, _path), do: nil
end
