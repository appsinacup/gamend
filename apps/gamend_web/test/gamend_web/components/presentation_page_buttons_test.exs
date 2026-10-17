defmodule GamendWeb.Components.PresentationPageButtonsTest do
  @moduledoc """
  Config buttons: a `badge` after the label, and `disabled` for something
  announced and not there yet — drawn as the button, never a link.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage

  defp render_buttons(buttons) do
    render_component(&PresentationPage.buttons/1, buttons: buttons)
  end

  test "a plain button is a link with no badge" do
    html = render_buttons([%{"label" => "Tests", "href" => "/tests"}])

    assert html =~ ~s(href="/tests")
    refute html =~ "badge"
  end

  test "a badge renders after the label" do
    html = render_buttons([%{"label" => "Classes", "href" => "/classes", "badge" => "Pro"}])

    assert html =~ ~s(href="/classes")
    assert html =~ ~r/Classes.*badge.*Pro/s
  end

  test "a disabled button is not a link, even with an href" do
    html =
      render_buttons([
        %{"label" => "Play", "href" => "/play", "badge" => "Coming soon", "disabled" => true}
      ])

    refute html =~ "<a"
    refute html =~ "/play"
    assert html =~ ~s(aria-disabled="true")
    assert html =~ "Coming soon"
  end

  test "a disabled button needs no href" do
    html = render_buttons([%{"label" => "iOS", "disabled" => true}])

    assert html =~ "iOS"
    assert html =~ ~s(aria-disabled="true")
  end

  test "an enabled button without an href is still dropped" do
    assert render_buttons([%{"label" => "Nowhere"}]) =~ ~r/^\s*$/
  end

  test "a badge on a coloured button takes its content colour" do
    html =
      render_buttons([
        %{"label" => "Play", "href" => "/play", "style" => "primary", "badge" => "New"}
      ])

    assert html =~ "text-current"
    refute html =~ "badge-primary"
  end
end
