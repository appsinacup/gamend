defmodule GamendWeb.Components.BackLinkTest do
  @moduledoc """
  Every page under home opens its title row with `<.back_link>` (2026-10-09):
  one arrow, one RTL mirror, the word hidden on a phone but still the link's
  name. The pages one step under home point it at `home_path/0`.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GamendWeb.CoreComponents

  test "takes a live route or a plain one, mirrored in RTL, named on a phone" do
    live = render_component(&CoreComponents.back_link/1, navigate: "/x")
    plain = render_component(&CoreComponents.back_link/1, href: "/y")

    assert live =~ ~s(href="/x")
    assert plain =~ ~s(href="/y")
    assert plain =~ "rtl:-scale-x-100"
    assert plain =~ ~s(title="Back")
    assert plain =~ ~s(class="sr-only sm:not-sr-only")
  end

  test "the header's Back takes a plain page too" do
    html =
      render_component(&CoreComponents.header/1,
        back_href: "/",
        inner_block: [%{inner_block: fn _, _ -> "Title" end}]
      )

    assert html =~ ~s(href="/")
    assert html =~ "hero-arrow-left-solid"
  end

  # The pages one step under home: Back goes home.
  for path <- ~w(/leaderboards /quests /roadmap /changelog /users/log_in /users/register) do
    test "#{path} has Back to home", %{conn: conn} do
      {:ok, _view, html} = live(conn, unquote(path))
      assert html =~ ~r/<a[^>]*href="\/"[^>]*title="Back"/
    end
  end

  test "the legal pages have Back to home", %{conn: conn} do
    for path <- ~w(/privacy /terms /data_deletion) do
      assert conn |> get(path) |> html_response(200) =~ ~r/<a[^>]*href="\/"[^>]*title="Back"/
    end
  end
end
