defmodule GamendWeb.TimeTextTest do
  @moduledoc """
  The server's half of relative times and spans. `local_time.js` counts with
  the same ladder (`local_time.test.mjs` pins the same boundaries), so the first
  paint and the script never disagree about the unit.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.TimeText

  doctest GamendWeb.TimeText

  @now ~U[2026-11-16 12:00:00Z]
  @minute 60
  @hour 3_600
  @day 86_400

  defp at(seconds, opts \\ []), do: TimeText.relative(DateTime.add(@now, seconds), @now, opts)

  describe "relative/3" do
    test "one unit, the largest that fits, both directions" do
      assert at(-12) == "12s ago"
      assert at(-7 * @minute) == "7m ago"
      assert at(7 * @minute) == "in 7m"
      assert at(-3 * @hour - 59 * @minute) == "3h ago"
      assert at(-@day) == "1 day ago"
      assert at(12 * @day) == "in 1 week"
      assert at(-29 * @day) == "4 weeks ago"
      assert at(-30 * @day) == "1 month ago"
      assert at(-61 * @day) == "2 months ago"
      assert at(-400 * @day) == "1 year ago"
      assert at(800 * @day) == "in 2 years"
    end

    test "every rung's boundary" do
      assert TimeText.parts(59) == {59, :second}
      assert TimeText.parts(60) == {1, :minute}
      assert TimeText.parts(@hour - 1) == {59, :minute}
      assert TimeText.parts(@hour) == {1, :hour}
      assert TimeText.parts(@day - 1) == {23, :hour}
      assert TimeText.parts(@day) == {1, :day}
      assert TimeText.parts(7 * @day - 1) == {6, :day}
      assert TimeText.parts(7 * @day) == {1, :week}
      assert TimeText.parts(30 * @day - 1) == {4, :week}
      assert TimeText.parts(30 * @day) == {1, :month}
      assert TimeText.parts(364 * @day) == {11, :month}
      assert TimeText.parts(365 * @day) == {1, :year}
    end

    test "never under a second, and a known past stays past" do
      assert at(0) == "1s ago"
      assert at(90, past: true) == "1m ago"
    end
  end

  describe "duration/2" do
    test "the largest unit and the one under it, the smaller dropped at zero" do
      assert TimeText.duration(0) == "0s"
      assert TimeText.duration(45) == "45s"
      assert TimeText.duration(541) == "9m 1s"
      assert TimeText.duration(75 * @minute + 3) == "1h 15m"
      assert TimeText.duration(2 * @day + 3 * @hour + 15 * @minute) == "2d 3h"
      assert TimeText.duration(2 * @day + 5 * @minute) == "2d"
      assert TimeText.duration(-5) == "0s"
    end

    test "one unit for an estimate" do
      assert TimeText.duration(541, units: 1) == "9m"
      assert TimeText.duration(2 * @day + 3 * @hour, units: 1) == "2d"
    end
  end
end
