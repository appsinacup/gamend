defmodule Gamend.TimeLintTest do
  use ExUnit.Case, async: true

  alias Gamend.TimeLint

  defp rules(source), do: source |> TimeLint.offenses_in("x_live.ex") |> Enum.map(& &1.rule)

  test "a date written out by hand" do
    assert rules(~S|  {Calendar.strftime(@build.inserted_at, "%Y-%m-%d %H:%M UTC")}|) == [
             :strftime
           ]

    assert rules(~S|  <td>{Date.to_iso8601(row.day)}</td>|) == [:iso8601]
    assert rules(~S|  "uploaded #{DateTime.to_iso8601(at)}"|) == [:iso8601]
  end

  test "a DateTime interpolated raw" do
    assert rules(~S|  <td class="text-xs">{t.starts_at}</td>|) == [:raw_instant]
    assert rules(~S|  {@user.inserted_at}|) == [:raw_instant]
  end

  test "a relative phrase built by hand" do
    assert rules(~S|  seconds -> gettext("%{count}m ago", count: div(seconds, 60))|) == [
             :relative_phrase
           ]

    assert rules(~S|  {gettext("Ends in %{time}", time: t)}|) == [:relative_phrase]

    assert rules(~S|  ngettext("%{count} day left", "%{count} days left", n)|) == [
             :relative_phrase
           ]
  end

  test "what a machine reads, an option's span and a component's attribute pass" do
    assert rules(~S|  <time datetime={DateTime.to_iso8601(@at)}>|) == []
    assert rules(~S|  <.timestamp at={@user.inserted_at} />|) == []
    assert rules(~S|  {ngettext("In %{count} day", "In %{count} days", days)}|) == []
    assert rules(~S|  {gettext("More in %{category}", category: c)}|) == []
  end

  test "a marked line, on it or above it, and a comment pass" do
    assert rules("""
           # time-ok: an axis label
           defp label(day), do: Calendar.strftime(day, "%m-%d")
           """) == []

    assert rules(~S|  Calendar.strftime(d, "%m") # time-ok: a filename|) == []
    assert rules(~S|  # Calendar.strftime(d, "%m") is what this replaced|) == []
  end
end
