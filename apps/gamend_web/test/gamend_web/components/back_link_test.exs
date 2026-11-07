defmodule GamendWeb.Components.BackLinkTest do
  @moduledoc """
  Every page under another page opens its title row with `<.back_link>`
  (2026-10-09): one arrow, one RTL mirror, the word hidden on a phone but
  still the link's name. A page one step under home has none: the navbar,
  the footer or the account menu opened it and is on screen (2026-11-07).
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

  # `back_link.js` takes a click on it back to the page the reader came from,
  # when they came by a click inside the site; the link is the fallback.
  test "is marked for back_link.js, live or plain" do
    assert render_component(&CoreComponents.back_link/1, navigate: "/x") =~ "data-back"
    assert render_component(&CoreComponents.back_link/1, href: "/y") =~ "data-back"
  end

  # The walk skips entries of the current path, so a parent on the same path
  # is followed as a link.
  test "a patch is not marked for back_link.js" do
    html = render_component(&CoreComponents.back_link/1, patch: "/x")

    assert html =~ ~s(href="/x")
    assert html =~ ~s(data-phx-link="patch")
    refute html =~ "data-back"
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

  # The pages one step under home: no Back.
  for path <- ~w(/leaderboards /quests /roadmap /changelog /users/log_in /users/register) do
    test "#{path} has no Back", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))
      refute has_element?(view, "a[title='Back']")
    end
  end

  test "the legal pages have no Back", %{conn: conn} do
    for path <- ~w(/privacy /terms /data_deletion) do
      refute conn |> get(path) |> html_response(200) =~ ~s(title="Back")
    end
  end
end
