defmodule GamendWeb.Components.TimestampTest do
  @moduledoc """
  The server never knows the reader's zone, so `<.timestamp>` renders the UTC
  instant plus the marks `local_time.js` needs to rewrite it. These pin the
  contract between the two halves: change an attribute name here and the page
  silently stops localizing, which no page test would notice.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.CoreComponents

  @at ~U[2026-08-01 23:30:00Z]

  test "carries the machine-readable instant and the localizer's marks" do
    html = render_component(&CoreComponents.timestamp/1, at: @at, format: "datetime")

    assert html =~ ~s(datetime="2026-08-01T23:30:00Z")
    assert html =~ ~s(data-local-time="datetime")
  end

  test "is relative unless told otherwise" do
    assert render_component(&CoreComponents.timestamp/1, at: @at) =~
             ~s(data-local-time="relative")
  end

  test "the fallback text names the zone whenever it shows an hour" do
    assert render_component(&CoreComponents.timestamp/1, at: @at, format: "datetime") =~
             "2026-08-01 23:30 UTC"

    assert render_component(&CoreComponents.timestamp/1, at: @at, format: "time") =~ "23:30 UTC"

    assert render_component(&CoreComponents.timestamp/1, at: @at, format: "full") =~
             "2026-08-01 23:30:00 UTC"

    # A date alone cannot be misread as a local hour, and the localizer still
    # corrects it across a midnight boundary.
    date = render_component(&CoreComponents.timestamp/1, at: @at, format: "date")
    assert date =~ "Aug 1, 2026"
    refute date =~ "UTC"
  end

  test "a naive value is treated as the UTC instant it is" do
    html = render_component(&CoreComponents.timestamp/1, at: ~N[2026-08-01 23:30:00])

    assert html =~ ~s(datetime="2026-08-01T23:30:00Z")
  end

  describe "a calendar date" do
    # A publication day is not an instant, and must not shift across midnight,
    # but with no localizer mark at all every date on the site would stay in
    # English. `calendar-date` has the localizer translate it with the zone
    # pinned to UTC.
    test "carries the calendar mark and the bare ISO date, not an instant" do
      html = render_component(&CoreComponents.timestamp/1, at: ~D[2026-09-16])

      assert html =~ ~s(datetime="2026-09-16")
      assert html =~ ~s(data-local-time="calendar-date")
      refute html =~ "T00:00"
    end

    test "falls back to a readable English date without JS" do
      html = render_component(&CoreComponents.timestamp/1, at: ~D[2026-09-16])

      assert html =~ "Sep 16, 2026"
      refute html =~ "UTC"
    end
  end

  describe "a relative time" do
    defp ago(seconds) do
      at = DateTime.add(DateTime.utc_now(), -seconds, :second)
      render_component(&CoreComponents.timestamp/1, at: at)
    end

    test "carries the localizer's mark and the exact time on hover" do
      html = ago(200)

      assert html =~ ~s(data-local-time="relative")
      assert html =~ ~r/title="\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC"/
    end

    test "is terse up to the hour and spelled out from a day" do
      assert ago(30) =~ ~r/\d+s ago/
      assert ago(200) =~ "3m ago"
      assert ago(3_700) =~ "1h ago"
      assert ago(90_000) =~ "1 day ago"
      assert ago(2 * 86_400 + 10) =~ "2 days ago"
      assert ago(13 * 86_400) =~ "1 week ago"
      assert ago(40 * 86_400) =~ "1 month ago"
      assert ago(400 * 86_400) =~ "1 year ago"
    end

    test "a future instant is how long until it" do
      html = ago(-(12 * 86_400 + 60))

      assert html =~ "in 1 week"
      refute html =~ "data-local-time-past"
    end

    test "a past instant is marked so a slow browser clock keeps it past" do
      assert ago(200) =~ "data-local-time-past"
    end

    test "only a relative time carries a title" do
      refute render_component(&CoreComponents.timestamp/1, at: @at, format: "datetime") =~
               "title="
    end
  end

  describe "a duration" do
    defp duration(attrs), do: render_component(&CoreComponents.duration/1, attrs)

    test "says a span in its two largest units" do
      html = duration(seconds: 541)

      assert html =~ "9m 1s"
      assert html =~ ~s(datetime="PT541S")
      assert html =~ ~s(data-local-duration="541")
      refute html =~ "data-local-duration-from"
    end

    test "takes milliseconds, one unit, or the two ends of the span" do
      assert duration(ms: 541_900) =~ "9m 1s"
      assert duration(seconds: 541, units: 1) =~ "9m"
      refute duration(seconds: 541, units: 1) =~ "9m 1s"
      assert duration(from: ~U[2026-08-01 10:00:00Z], to: ~U[2026-08-01 12:05:30Z]) =~ "2h 5m"
    end

    test "a span with no end is still running and counts up" do
      from = DateTime.add(DateTime.utc_now(), -75, :second)
      html = duration(from: from)

      assert html =~ "data-local-duration-from"
      assert html =~ ~r/1m 1[56]s/
    end

    test "no span renders the placeholder" do
      assert duration(from: nil) == "-"
      assert duration(seconds: nil, empty: "—") == "—"
    end
  end

  test "nil renders the placeholder and nothing for the localizer to touch" do
    assert render_component(&CoreComponents.timestamp/1, at: nil) == "-"
    assert render_component(&CoreComponents.timestamp/1, at: nil, empty: "never") == "never"
  end
end
