defmodule GameServerWeb.HostPublicDocs do
  @moduledoc """
  Renders the guides in `priv/docs` as one page of expandable sections.

  A guide is a markdown file and nothing else: the folder gives its category,
  the numeric filename prefix its order, the first heading its title, and
  optional front matter its heroicon. A folder's `_category.md` names the
  category and gives it an icon and a colour, which its guides inherit so each
  section reads as one group. Adding
  one takes no Elixir change, which is the whole point — the previous version
  of this page carried 9k lines of hand-written HEEx for the same content.

  Sections are native `<details>`, so expanding one needs no JavaScript and
  works with find-in-page and keyboard navigation.

  Which guide is open lives in the query string (`/docs/setup?guide=payments`)
  rather than in a fragment: a fragment never reaches the server, so it could
  neither be restored after a websocket reconnect nor rendered into the initial
  HTML. A query param survives both, and the URL stays copy-pasteable.
  """

  use GameServerWeb, :live_view

  alias GameServer.Content

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.header>
          <h1 class="text-3xl font-bold">{gettext("Setup & Guides")}</h1>
          <:subtitle>
            {gettext("Platform setup, OAuth providers, payments, email, and server hooks")}
          </:subtitle>
        </.header>

        <p :if={@categories == []} class="text-base-content/60">
          {gettext("No guides found.")}
        </p>

        <section :for={category <- @categories} class="space-y-2">
          <h2 class="font-semibold uppercase tracking-[0.24em] border-t border-base-300/60 pt-6 flex items-center gap-2">
            <.icon name={category.icon} class={"size-5 #{category.color}"} />
            {category.category}
          </h2>

          <details
            :for={guide <- category.guides}
            id={guide.slug}
            class="card bg-base-100 shadow-sm group"
            open={guide.slug == @open}
            phx-hook="GuideDisclosure"
            data-slug={guide.slug}
          >
            <summary class="card-body cursor-pointer list-none py-4 flex-row items-center gap-3">
              <.icon name={guide.icon} class={"size-6 shrink-0 opacity-80 #{category.color}"} />
              <span class="card-title text-xl shrink-0">{guide.title}</span>
              <span class="text-sm text-base-content/50 grow line-clamp-1">{guide.summary}</span>
              <.icon
                name="hero-chevron-down"
                class="size-4 shrink-0 transition-transform group-open:rotate-180"
              />
            </summary>

            <div class="card-body pt-0 markdown-content">
              {raw(Content.doc_html(guide.slug))}
            </div>
          </details>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Documentation"))
     |> assign(:categories, Content.list_doc_categories())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :open, params["guide"])}
  end

  # Opening or closing a section rewrites the URL without a server round trip
  # for the content, which is already on the page.
  @impl true
  def handle_event("guide_toggled", %{"slug" => slug, "open" => true}, socket) do
    {:noreply, socket |> assign(:open, slug) |> push_patch(to: ~p"/docs/setup?guide=#{slug}")}
  end

  def handle_event("guide_toggled", %{"slug" => slug}, socket) do
    if socket.assigns.open == slug do
      {:noreply, socket |> assign(:open, nil) |> push_patch(to: ~p"/docs/setup")}
    else
      {:noreply, socket}
    end
  end
end
