defmodule GamendWeb.BlogLive do
  @moduledoc """
  `/blog` and `/blog/:slug`, rendered from the registered `:blog` directory.

  The page is `GamendWeb.ContentPages.blog_index/1` and `blog_post/1`, so no
  host writes it itself; a host that wants something else routes its own
  module, which the route macro allows.
  """

  use GamendWeb, :live_view

  alias Gamend.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Blog"))
     |> assign(:blog_available?, Content.path(:blog) != nil)
     |> assign(:changelog_available?, Content.path(:changelog) != nil)
     |> assign(:roadmap_available?, Content.path(:roadmap) != nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Blog"))
    |> assign(:grouped_posts, Content.blog_posts_grouped())
    |> assign(:post, nil)
  end

  defp apply_action(socket, :show, %{"slug" => slug}) do
    case Content.get_blog_post(slug) do
      nil ->
        socket
        |> put_flash(:error, gettext("No results."))
        |> push_navigate(to: ~p"/blog")

      post ->
        {prev, next} = Content.blog_neighbours(slug)

        socket
        |> assign(:page_title, post.title)
        |> assign(:post, post)
        |> assign(:post_html, Content.blog_post_html(slug))
        |> assign(:prev_post, prev)
        |> assign(:next_post, next)
    end
  end

  @impl true
  def render(%{post: %{} = _post} = assigns) do
    ~H"""
    <GamendWeb.ContentPages.blog_post
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      post={@post}
      html={@post_html}
      prev={@prev_post}
      next={@next_post}
    />
    """
  end

  def render(assigns) do
    ~H"""
    <GamendWeb.ContentPages.blog_index
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      blog_available?={@blog_available?}
      grouped_posts={assigns[:grouped_posts] || []}
      changelog_available?={@changelog_available?}
      roadmap_available?={@roadmap_available?}
    />
    """
  end
end
