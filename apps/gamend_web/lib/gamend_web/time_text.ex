defmodule GamendWeb.TimeText do
  @moduledoc """
  How far an instant is from now ("7m ago", "in 12 days") and how long a span
  lasted ("9m 1s"), as short English text.

  This is the server's half. `<.timestamp>` and `<.duration>` paint it first and
  `local_time.js` says the same thing again in the reader's language, counting
  with the same ladder (`relativeParts`, `durationParts`), so the page does not
  change its mind when the script runs. Reach for these functions directly only
  where no element can go: a flash, a stat card's value, an `<option>`.

  One unit only, the largest that fits, floored: 13 days is "1 week ago",
  never "1 week 6 days ago". The exact moment is the element's title.
  """

  @minute 60
  @hour 3_600
  @day 86_400
  @week 7 * @day
  @month 30 * @day
  @year 365 * @day

  @typedoc "A ladder rung: how many, of which unit."
  @type unit :: :second | :minute | :hour | :day | :week | :month | :year

  @doc """
  `at` relative to `now`: "12s ago", "7m ago", "3h ago", "5 days ago",
  "1 week ago", "2 months ago", "1 year ago", and "in …" for a future instant.

  `past: true` says the instant is known to be behind us (a row's insert
  time): a clock a little ahead of it still says "1s ago", never "in 2s".
  """
  @spec relative(DateTime.t(), DateTime.t(), keyword()) :: String.t()
  def relative(%DateTime{} = at, %DateTime{} = now \\ DateTime.utc_now(), opts \\ []) do
    diff = DateTime.diff(at, now)
    future? = diff > 0 and not Keyword.get(opts, :past, false)
    {count, unit} = parts(abs(diff))

    phrase = say(count, unit)
    if future?, do: "in " <> phrase, else: phrase <> " ago"
  end

  @doc """
  The rung for a distance of `seconds` (sign ignored), never under a second.

      iex> GamendWeb.TimeText.parts(200)
      {3, :minute}
      iex> GamendWeb.TimeText.parts(13 * 86_400)
      {1, :week}
  """
  @spec parts(integer()) :: {pos_integer(), unit()}
  def parts(seconds) when is_integer(seconds) do
    s = max(abs(seconds), 1)

    cond do
      s < @minute -> {s, :second}
      s < @hour -> {div(s, @minute), :minute}
      s < @day -> {div(s, @hour), :hour}
      s < @week -> {div(s, @day), :day}
      s < @month -> {div(s, @week), :week}
      # 360 to 364 days would floor to "12 months": still under a year.
      s < @year -> {min(div(s, @month), 11), :month}
      true -> {div(s, @year), :year}
    end
  end

  @doc """
  A span of `seconds` in its largest unit and the one under it: "45s",
  "9m 1s", "3h 5m", "2d 3h". The smaller unit is left out when it is zero
  ("2d", not "2d 0h"). `units: 1` keeps only the largest ("~3m" estimates).

      iex> GamendWeb.TimeText.duration(541)
      "9m 1s"
      iex> GamendWeb.TimeText.duration(541, units: 1)
      "9m"
  """
  @spec duration(integer(), keyword()) :: String.t()
  def duration(seconds, opts \\ []) when is_integer(seconds) do
    units = Keyword.get(opts, :units, 2)

    seconds
    |> max(0)
    |> duration_parts(units)
    |> Enum.map_join(" ", fn {count, label} -> "#{count}#{label}" end)
  end

  @doc """
  The pieces of `duration/2`: `[{9, "m"}, {1, "s"}]`. Always at least one,
  so a zero-length span is `[{0, "s"}]`.
  """
  @spec duration_parts(non_neg_integer(), pos_integer()) :: [{non_neg_integer(), String.t()}]
  def duration_parts(seconds, units \\ 2) do
    all = [
      {div(seconds, @day), "d"},
      {div(rem(seconds, @day), @hour), "h"},
      {div(rem(seconds, @hour), @minute), "m"},
      {rem(seconds, @minute), "s"}
    ]

    case Enum.drop_while(all, fn {count, _label} -> count == 0 end) do
      [] ->
        [{0, "s"}]

      [largest | smaller] ->
        [largest | smaller |> Enum.take(units - 1) |> Enum.reject(&(elem(&1, 0) == 0))]
    end
  end

  @doc """
  The instant as UTC text, labelled wherever it shows an hour: what a page
  shows before `local_time.js` puts it in the reader's zone, or without it.
  `format` is one of `<.timestamp>`'s absolute ones. "date" reads as
  `dateStyle: "medium"` does in English ("Sep 8, 2026"), so the page does not
  reflow when the script runs; a date alone needs no zone, since the script
  corrects it across a midnight boundary anyway.
  """
  @spec utc(DateTime.t() | Date.t(), String.t()) :: String.t()
  def utc(at, "date"), do: Calendar.strftime(at, "%b %-d, %Y")
  def utc(at, "time"), do: Calendar.strftime(at, "%H:%M UTC")
  def utc(at, "full"), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")
  def utc(at, _datetime), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  # Terse up to the hour, spelled out from a day: what
  # `Intl.RelativeTimeFormat` says in English for the styles `local_time.js` picks.
  defp say(count, :second), do: "#{count}s"
  defp say(count, :minute), do: "#{count}m"
  defp say(count, :hour), do: "#{count}h"
  defp say(1, unit), do: "1 #{unit}"
  defp say(count, unit), do: "#{count} #{unit}s"
end
