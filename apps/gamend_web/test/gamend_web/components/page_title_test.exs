defmodule GamendWeb.Components.PageTitleTest do
  @moduledoc """
  `header/1` draws a page's title with its mark, in its navbar link's colour
  when the host gives one.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  import GamendWeb.CoreComponents, only: [header: 1]

  test "a tone colours the mark" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.header icon="hero-book-open-solid" tone="guides">Guides</.header>
      """)

    assert html =~ ~s(data-tone="guides")
    assert html =~ "hero-book-open-solid"
    assert html =~ "text-(--nav-tone)"
  end

  test "with no tone the mark is muted" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.header icon="hero-book-open-solid">Guides</.header>
      """)

    refute html =~ "data-tone"
    assert html =~ "text-muted"
  end
end
