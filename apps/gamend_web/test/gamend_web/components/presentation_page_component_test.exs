defmodule GamendWeb.Components.PresentationPageComponentTest do
  @moduledoc """
  A section's `"component"` names a block the host draws itself, resolved
  through `config :gamend_web, :presentation_components`.
  """
  # `put_env` is process-wide, so never alongside another test's reading.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage

  defmodule Demo do
    use Phoenix.Component

    def strip(assigns) do
      ~H"""
      <p id="demo-strip">{@section["title"]}: every language</p>
      """
    end
  end

  setup do
    previous = Application.get_env(:gamend_web, :presentation_components)
    Application.put_env(:gamend_web, :presentation_components, %{"demo" => {Demo, :strip}})

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:gamend_web, :presentation_components)
        map -> Application.put_env(:gamend_web, :presentation_components, map)
      end
    end)

    :ok
  end

  defp render_section(section) do
    render_component(&PresentationPage.section/1, section: section)
  end

  test "a section's component is drawn by the host function it names, in both layouts" do
    for layout <- [%{"media_layout" => "full"}, %{}] do
      html =
        render_section(Map.merge(%{"title" => "Languages", "component" => "demo"}, layout))

      assert html =~ ~s(<p id="demo-strip">Languages: every language</p>)
      # After the title, so the block reads as the section's body.
      assert [before_title, after_title] = String.split(html, "</h2>", parts: 2)
      assert before_title =~ "Languages"
      assert after_title =~ "demo-strip"
    end
  end

  test "a name the host does not register draws nothing and is logged" do
    log =
      capture_log(fn ->
        html = render_section(%{"title" => "T", "component" => "nope"})
        refute html =~ "demo-strip"
      end)

    assert log =~ ~s(component the host does not register: "nope")
  end

  test "a section with no component is as it was" do
    log =
      capture_log(fn ->
        html = render_section(%{"title" => "T", "text" => "Plain."})
        assert html =~ "Plain."
        refute html =~ "demo-strip"
      end)

    refute log =~ "does not register"
  end
end
