defmodule GameServerWeb.Components.TimestampTest do
  @moduledoc """
  The server never knows the reader's zone, so `<.timestamp>` renders the UTC
  instant plus the marks `local_time.js` needs to rewrite it. These pin the
  contract between the two halves: change an attribute name here and the page
  silently stops localizing, which no page test would notice.
  """
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GameServerWeb.CoreComponents

  @at ~U[2026-08-01 23:30:00Z]

  test "carries the machine-readable instant and the localizer's marks" do
    html = render_component(&CoreComponents.timestamp/1, at: @at)

    assert html =~ ~s(datetime="2026-08-01T23:30:00Z")
    assert html =~ ~s(data-local-time="datetime")
  end

  test "the fallback text names the zone whenever it shows an hour" do
    assert render_component(&CoreComponents.timestamp/1, at: @at) =~ "2026-08-01 23:30 UTC"
    assert render_component(&CoreComponents.timestamp/1, at: @at, format: "time") =~ "23:30 UTC"

    assert render_component(&CoreComponents.timestamp/1, at: @at, format: "full") =~
             "2026-08-01 23:30:00 UTC"

    # A date alone cannot be misread as a local hour, and the localizer still
    # corrects it across a midnight boundary.
    date = render_component(&CoreComponents.timestamp/1, at: @at, format: "date")
    assert date =~ "Aug 01, 2026"
    refute date =~ "UTC"
  end

  test "a naive value is treated as the UTC instant it is" do
    html = render_component(&CoreComponents.timestamp/1, at: ~N[2026-08-01 23:30:00])

    assert html =~ ~s(datetime="2026-08-01T23:30:00Z")
  end

  test "nil renders the placeholder and nothing for the localizer to touch" do
    assert render_component(&CoreComponents.timestamp/1, at: nil) == "-"
    assert render_component(&CoreComponents.timestamp/1, at: nil, empty: "never") == "never"
  end
end
