defmodule Gamend.IconsTest do
  use ExUnit.Case, async: false

  alias Gamend.Icons

  test "an icon's URL carries one of the site's colours, and nothing else" do
    assert Icons.path("trophy") == "/icons/trophy.svg"
    assert Icons.path("trophy", "info") == "/icons/trophy.svg?color=info"
    assert Icons.path("trophy", "nope") == "/icons/trophy.svg"

    assert Icons.name("/icons/trophy.svg?color=info") == "trophy"
    assert Icons.color("/icons/trophy.svg?color=info") == "info"
    assert Icons.color("/icons/trophy.svg") == nil

    # A colour the site no longer has keeps the icon, drawn in none.
    assert Icons.name("/icons/trophy.svg?color=gone") == "trophy"
    assert Icons.color("/icons/trophy.svg?color=gone") == nil

    # Any other query is not an icon's URL.
    assert Icons.name("/icons/trophy.svg?x=https://evil.example") == nil
    assert Icons.name("/icons/trophy.svg?color=a&b=c") == nil
  end

  test "the theme's colours by default, each its CSS variable" do
    assert Icons.colors() == ~w(primary info success warning error)
    assert Icons.color_css("primary") == "var(--color-primary)"
    assert Icons.color_css("nope") == nil
  end

  test "a host names its own colours" do
    Application.put_env(:gamend_core, Icons, colors: ["accent", {"rose", "#e11d48"}])
    on_exit(fn -> Application.delete_env(:gamend_core, Icons) end)

    assert Icons.colors() == ["accent", "rose"]
    assert Icons.color_css("accent") == "var(--color-accent)"
    assert Icons.color_css("rose") == "#e11d48"
    assert Icons.path("star", "rose") == "/icons/star.svg?color=rose"
  end

  test "put_color/2 puts the colour picked beside an icon on its URL" do
    assert Icons.put_color(
             %{"icon_url" => "/icons/star.svg", "icon_url_color" => "error"},
             "icon_url"
           ) ==
             %{"icon_url" => "/icons/star.svg?color=error"}

    # None picked: the URL's own stays.
    assert Icons.put_color(%{"icon_url" => "/icons/star.svg?color=info"}, "icon_url") ==
             %{"icon_url" => "/icons/star.svg?color=info"}

    # No colour: none.
    assert Icons.put_color(
             %{"icon_url" => "/icons/star.svg?color=info", "icon_url_color" => ""},
             "icon_url"
           ) == %{"icon_url" => "/icons/star.svg"}

    # An upload is no icon: no colour on it.
    assert Icons.put_color(
             %{"icon_url" => "/storage/icons/a.png", "icon_url_color" => "info"},
             "icon_url"
           ) == %{"icon_url" => "/storage/icons/a.png"}
  end

  test "for_id/1 is one icon in one colour, the same for the same id" do
    url = Icons.for_id("some-id")
    assert url == Icons.for_id("some-id")
    assert Icons.name(url) in Icons.picks()
    assert Icons.color(url) in Icons.colors()
  end
end
