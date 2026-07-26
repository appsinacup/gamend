defmodule GameServerWeb.HostBlogLive do
  @moduledoc """
  Host-owned LiveView for the blog section.

  - `:index` lists all blog posts grouped by year and month
  - `:show` renders an individual post with next/prev navigation
  """

  use GameServerWeb, :live_view

  alias GameServer.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Blog")
     |> assign(:blog_available?, Content.path(:blog) != nil)
     |> assign(:changelog_available?, Content.path(:changelog) != nil)
     |> assign(:roadmap_available?, Content.path(:roadmap) != nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    grouped = group_blog_posts(Content.list_blog_posts())

    socket
    |> assign(:page_title, "Blog")
    |> assign(:grouped_posts, grouped)
    |> assign(:post, nil)
    |> assign(:post_html, nil)
    |> assign(:prev_post, nil)
    |> assign(:next_post, nil)
  end

  defp apply_action(socket, :show, %{"slug" => slug}) do
    post = Content.get_blog_post(slug)

    if post do
      html = Content.blog_post_html(slug)
      {prev, next} = Content.blog_neighbours(slug)

      socket
      |> assign(:page_title, post.title)
      |> assign(:post, post)
      |> assign(:post_html, html)
      |> assign(:prev_post, prev)
      |> assign(:next_post, next)
      |> assign(:grouped_posts, [])
    else
      socket
      |> put_flash(:error, "Blog post not found")
      |> push_navigate(to: ~p"/blog")
    end
  end

  defp group_blog_posts(posts) do
    posts
    |> Enum.group_by(fn post -> {post.date.year, post.date.month} end)
    |> Enum.sort_by(fn {{year, month}, _posts} -> {year, month} end, :desc)
    |> Enum.group_by(fn {{year, _month}, _posts} -> year end, fn {{_year, month}, month_posts} ->
      {month, month_posts}
    end)
    |> Enum.sort_by(fn {year, _months} -> year end, :desc)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="py-8 px-4 sm:px-6 max-w-4xl mx-auto">
        <%= if !@blog_available? do %>
          <div class="text-center py-20">
            <.icon name="hero-newspaper" class="w-16 h-16 mx-auto text-base-content/30 mb-4" />
            <h2 class="text-xl font-semibold text-base-content/60 mb-2">
              {gettext("No results.")}
            </h2>
            <p class="text-base-content/40">
              Add blog Markdown files under blog to display posts here.
            </p>
          </div>
        <% else %>
          <%= if @live_action == :show && @post do %>
            <.blog_post post={@post} html={@post_html} prev={@prev_post} next={@next_post} />
          <% else %>
            <.blog_index
              grouped_posts={@grouped_posts}
              changelog_available={@changelog_available?}
              roadmap_available={@roadmap_available?}
            />
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp blog_index(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-8">
      <h1 class="text-3xl font-bold">{gettext("Blog")}</h1>
      <div class="flex items-center gap-3">
        <.link
          :if={@roadmap_available}
          navigate={~p"/roadmap"}
          class="inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-primary transition-colors"
        >
          <.icon name="hero-map" class="w-4 h-4" /> {gettext("Roadmap")}
        </.link>
        <.link
          :if={@changelog_available}
          navigate={~p"/changelog"}
          class="inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-primary transition-colors"
        >
          <.icon name="hero-document-text" class="w-4 h-4" /> {gettext("Changelog")}
        </.link>
      </div>
    </div>

    <%= if @grouped_posts == [] do %>
      <div class="text-center py-16">
        <.icon name="hero-pencil-square" class="w-12 h-12 mx-auto text-base-content/30 mb-3" />
        <p class="text-base-content/50">{gettext("No results.")}</p>
      </div>
    <% else %>
      <div class="space-y-10">
        <%= for {year, months} <- @grouped_posts do %>
          <section>
            <h2 class="text-2xl font-bold text-base-content/90 mb-6 border-b border-base-300 pb-2">
              {year}
            </h2>

            <%= for {month, posts} <- months do %>
              <div class="mb-8">
                <h3 class="text-sm font-semibold uppercase tracking-[0.22em] text-base-content/40 mb-4">
                  {month_name(month)}
                </h3>

                <div class="space-y-4">
                  <%= for post <- posts do %>
                    <article class="rounded-3xl border border-base-300 bg-base-100/95 p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
                      <.link navigate={~p"/blog/#{post.slug}"} class="block space-y-2">
                        <div class="flex items-center gap-2 text-xs uppercase tracking-[0.18em] text-base-content/40">
                          <span><.timestamp at={post.date} format="date" /></span>
                        </div>

                        <h4 class="text-xl font-semibold text-base-content/90 transition-colors hover:text-primary">
                          {post.title}
                        </h4>

                        <p class="text-sm leading-6 text-base-content/60">
                          {post.excerpt}
                        </p>
                      </.link>
                    </article>
                  <% end %>
                </div>
              </div>
            <% end %>
          </section>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp blog_post(assigns) do
    ~H"""
    <article class="space-y-10">
      <div class="space-y-4">
        <div class="flex flex-wrap items-center gap-3 text-xs uppercase tracking-[0.2em] text-base-content/40">
          <.link navigate={~p"/blog"} class="hover:text-primary transition-colors">
            {gettext("Blog")}
          </.link>
          <span>/</span>
          <span><.timestamp at={@post.date} format="date" /></span>
        </div>

        <div class="space-y-3">
          <h1 class="text-4xl font-bold leading-tight text-base-content/95 sm:text-5xl">
            {@post.title}
          </h1>
          <p class="max-w-2xl text-base leading-7 text-base-content/60">
            {@post.excerpt}
          </p>
        </div>
      </div>

      <article class="markdown-content">
        {Phoenix.HTML.raw(@html)}
      </article>

      <div class="grid gap-4 border-t border-base-300 pt-6 md:grid-cols-2">
        <div>
          <%= if @next do %>
            <.link
              navigate={~p"/blog/#{@next.slug}"}
              class="group flex h-full flex-col rounded-2xl border border-base-300 bg-base-100/90 p-4 transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md"
            >
              <span class="text-xs uppercase tracking-[0.2em] text-base-content/40">
                {gettext("Newer")}
              </span>
              <span class="mt-2 text-lg font-semibold text-base-content/90 group-hover:text-primary">
                {@next.title}
              </span>
            </.link>
          <% end %>
        </div>
        <div>
          <%= if @prev do %>
            <.link
              navigate={~p"/blog/#{@prev.slug}"}
              class="group flex h-full flex-col rounded-2xl border border-base-300 bg-base-100/90 p-4 text-right transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-md"
            >
              <span class="text-xs uppercase tracking-[0.2em] text-base-content/40">
                {gettext("Older")}
              </span>
              <span class="mt-2 text-lg font-semibold text-base-content/90 group-hover:text-primary">
                {@prev.title}
              </span>
            </.link>
          <% end %>
        </div>
      </div>
    </article>
    """
  end

  defp month_name(month) do
    Date.new!(2000, month, 1)
    |> Calendar.strftime("%B")
  end
end
