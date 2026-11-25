defmodule GamendWeb.ChangelogLive do
  @moduledoc """
  `/changelog`, rendered from the registered `:changelog` markdown file.

  The page is `GamendWeb.ContentPages.changelog/1`, so no host writes it
  itself; a host that wants something else routes its own module, which the
  route macro allows.
  """

  use GamendWeb, :live_view

  alias Gamend.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Changelog"))
     |> assign(:html, Content.changelog_html())
     |> assign(:roadmap_available?, Content.path(:roadmap) != nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <GamendWeb.ContentPages.changelog
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      html={@html}
      roadmap_available?={@roadmap_available?}
    />
    """
  end
end
