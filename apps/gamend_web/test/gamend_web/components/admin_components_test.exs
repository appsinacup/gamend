defmodule GamendWeb.AdminComponentsTest do
  @moduledoc """
  The admin console's heading and card, as core's pages and a host's use them.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GamendWeb.AdminComponents

  defp header(attrs), do: render_component(&AdminComponents.admin_header/1, attrs)
  defp card(attrs), do: render_component(&AdminComponents.admin_card/1, attrs)
  defp icon(attrs), do: render_component(&AdminComponents.admin_icon/1, attrs)

  test "a core page's heading comes from its table entry, with Back to /admin" do
    html = LazyHTML.from_fragment(header(page: "/admin/users"))

    assert html |> LazyHTML.query("h1") |> LazyHTML.text() |> String.trim() == "Users"
    assert LazyHTML.query(html, ~s|a[href="/admin"][data-back]|) |> Enum.count() == 1
    assert LazyHTML.query(html, ~s|span.hero-users-solid|) |> Enum.count() == 1
  end

  test "a page's own title wins over its table entry" do
    assert header(page: "/admin/geo", title: "Elsewhere") =~ "Elsewhere"
  end

  test "a host's page names itself" do
    html = header(title: "Builds", icon: "hero-cube", color: "violet", back: "/admin/tools")

    assert html =~ "Builds"
    assert html =~ "hero-cube"
    assert html =~ "text-violet-700"
    assert html =~ ~s(href="/admin/tools")
  end

  test "the dashboard has no Back" do
    refute header(title: "Admin Dashboard", back: nil) =~ "data-back"
  end

  test "a path the table does not know is a bug in the page" do
    assert_raise KeyError, fn -> header(page: "/admin/nope") end
  end

  test "a colour that is not one draws the neutral tile, and no icon the default mark" do
    html = icon(color: "chartreuse")

    assert html =~ "text-slate-700"
    assert html =~ "hero-squares-2x2"
  end

  test "a card links to its page, under the page's name" do
    html = LazyHTML.from_fragment(card(page: "/admin/kv", value: 3))

    assert LazyHTML.query(html, ~s|a[href="/admin/kv"]|) |> Enum.count() == 1
    assert LazyHTML.text(html) =~ "Key-Value"
    assert LazyHTML.text(html) =~ "3"
  end

  test "a card's one link is its title, and it is the site's card" do
    html = LazyHTML.from_fragment(card(title: "Cache", path: "/admin/x"))

    assert html |> LazyHTML.query("a") |> LazyHTML.text() |> String.trim() == "Cache"
    assert LazyHTML.query(html, "div.card.bg-base-200 > div.card-body") |> Enum.count() == 1
  end

  test "zero is a figure" do
    assert LazyHTML.from_fragment(card(title: "Logs", path: "/admin/logs", value: 0))
           |> LazyHTML.query("div.text-2xl")
           |> LazyHTML.text() =~ "0"
  end
end
