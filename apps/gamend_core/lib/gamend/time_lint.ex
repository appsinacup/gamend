defmodule Gamend.TimeLint do
  @moduledoc """
  Finds a time a page formats by hand. `mix gamend.time.lint` runs it.

  An instant a reader sees is `<.timestamp at={…} />` (relative by default,
  "7m ago", "in 12 days"), and a span is `<.duration>` (CONTRIBUTING.md, Time).
  Both are said again in the reader's zone and language, and the relative one
  stays current while the page is open. A hand-made format is none of that: a
  UTC hour that reads as local, English in every language, "3d ago" frozen at
  the moment the page was drawn.

  In a page's code (a LiveView, a component, a controller's HTML module, a
  `.heex` template) it reports:

    * `Calendar.strftime/2` and `to_iso8601`: a date written out by hand
    * `{@thing.inserted_at}`: a DateTime interpolated raw, which Elixir writes
      as "2026-11-15 14:23:00Z"
    * a hand-built relative phrase in gettext: "%{count}m ago", "Ends in
      %{time}", "%{count} days left"

  Plain text that cannot hold an element (a flash, an `<option>`, a stat
  card's value) uses `GamendWeb.TimeText`. A use that is right as it is (a
  chart's axis, a filename, a feed) is marked with the reason, on its line or
  the line above:

      # time-ok: an axis label, a calendar day
      defp label(%Date{} = day), do: Calendar.strftime(day, "%m-%d")

  It is a heuristic, read line by line, and says so.
  """

  @type offense :: %{file: String.t(), line: pos_integer(), rule: atom(), text: String.t()}

  @markers ["# time-ok:", "<%!-- time-ok:"]
  @comment_openers ["#", "<%!--"]

  # The engine and every host: `lib/`, an umbrella's apps, and plugins.
  @roots ["lib", "apps/*/lib", "modules/*/*/lib"]

  # Where a page is drawn. A context, a job, an API serializer or a mix task
  # writes times for machines and is not read here.
  @ui_paths ["/live/", "/components/", "_html/", "_html.ex", "_live.ex", "_component.ex"]

  @rules [
    strftime: ~r/Calendar\.strftime\(/,
    # Shown as text: a template line that is an interpolation, or a string's
    # `#{…}`. In an attribute (`datetime={…}`) it is for a machine.
    iso8601: ~r/(?:^\s*\{|>\s*\{|#\{)[^}]*\bto_iso8601\(/,
    # Not `at={@user.inserted_at}`: an attribute is the component's to format.
    raw_instant: ~r/(?<!=)\{@?[\w.]*_at\}/,
    relative_phrase:
      ~r/n?gettext\(\s*"[^"]*(?:\bago\b|\b(?:ends|closes|resets|expires|starts|opens|renews)\s+in\s+%\{|%\{\w+\}\s*(?:days?|hours?|minutes?|weeks?)\s+left)[^"]*"/i
  ]

  @doc "Every hand-made time in a page under the scan roots, by file and line."
  @spec offenses() :: [offense()]
  def offenses do
    @roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,heex}")))
    |> Enum.reject(&third_party?/1)
    |> Enum.filter(&ui?/1)
    |> Enum.uniq()
    |> Enum.flat_map(&offenses_in(File.read!(&1), &1))
    |> Enum.sort_by(&{&1.file, &1.line})
  end

  defp third_party?(path), do: String.contains?(path, ["/deps/", "/_build/", "/node_modules/"])

  defp ui?(path), do: String.ends_with?(path, ".heex") or String.contains?(path, @ui_paths)

  @doc "The hand-made times in one file's source."
  @spec offenses_in(String.t(), String.t()) :: [offense()]
  def offenses_in(source, path) do
    marked = marked_lines(source)

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {text, line} -> MapSet.member?(marked, line) or comment?(text) end)
    |> Enum.flat_map(fn {text, line} ->
      for {rule, pattern} <- @rules, Regex.match?(pattern, text) do
        %{file: path, line: line, rule: rule, text: String.trim(text)}
      end
    end)
  end

  defp comment?(text) do
    trimmed = String.trim_leading(text)
    String.starts_with?(trimmed, ["#", "<%!--"])
  end

  defp marked_lines(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {text, _line} -> String.contains?(text, @markers) end)
    |> Enum.map(fn {text, line} ->
      if text |> String.trim_leading() |> String.starts_with?(@comment_openers),
        do: line + 1,
        else: line
    end)
    |> MapSet.new()
  end
end
