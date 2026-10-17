defmodule GamendWeb.PageWidthTest do
  use ExUnit.Case, async: true

  # Three widths, no more. A page is the layout's column: the default, or
  # `wide` for a page with its own side columns (`Layouts.app wide`).
  # Anything narrower (a form, an article, a whole login page) is
  # `max-w-narrow` (`--container-narrow` in assets/css/app.css; every host
  # stylesheet declares it). Before this, pages picked their own: login at sm
  # then 4xl, legal pages at 2xl and 4xl, a blog post at 4xl, others at lg.
  #
  # A source scan, so a class built from pieces (`["mx-auto", width]`) slips
  # past it. Hosts carry the same test for their own pages.
  @lib Path.expand("../../lib", __DIR__)

  # The layout owns the column (and the footer and search palette beside it).
  @owner "gamend_web/components/host_layout_shell.ex"

  # A container size. `max-w-full`, `-none`, `-narrow` and spacing sizes
  # (`max-w-48`, an icon) are not a column width.
  @container ~r/^(xs|sm|md|lg|\d?xl|screen-[a-z0-9]+|prose|\[[\d.]+(rem|px|ch|em)\])$/

  defp sources do
    (@lib <> "/**/*.{ex,heex}")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, @owner))
    |> Enum.map(&{Path.relative_to(&1, @lib), File.read!(&1)})
  end

  test "a page is the layout's column, or max-w-narrow" do
    first_child = ~r/<Layouts\.app\b[^>]*>\s*<[a-z]+\b[^>]*class="([^"]*)"/s

    pages =
      for {path, source} <- sources(),
          [_, class] <- Regex.scan(first_child, source),
          width <- widths(class),
          do: "#{path}  #{width}"

    assert pages == [],
           """
           These pages set their own width on the column under Layouts.app:

           #{Enum.join(pages, "\n")}

           Drop it (the page is the layout's column; pass `wide` to Layouts.app
           for a page with its own side columns), or use `max-w-narrow`.
           """
  end

  test "a centred block is max-w-narrow" do
    offenders =
      for {path, source} <- sources(),
          {line, n} <- source |> String.split("\n") |> Enum.with_index(1),
          [string] <- Regex.scan(~r/"[^"]*"/, line, capture: :first),
          width <- centred_widths(string),
          do: "#{path}:#{n}  #{width}"

    assert offenders == [],
           """
           A centred block with its own width:

           #{Enum.join(offenders, "\n")}

           Use `mx-auto max-w-narrow`, the one narrow width, or no width (the page's).
           """
  end

  test "the stylesheet declares max-w-narrow" do
    css = File.read!(Path.expand("../../../../assets/css/app.css", __DIR__))
    assert css =~ "--container-narrow:"
  end

  # The `max-w-<container>` classes of a class string that also centres
  # (`mx-auto`, under any variant: `[&>*:not(header)]:mx-auto`, `sm:mx-auto`).
  defp centred_widths(string) do
    if Regex.match?(~r/(^|[\s":])mx-auto([\s"]|$)/, string), do: widths(string), else: []
  end

  defp widths(string) do
    string
    |> String.split(~r/[\s"]+/, trim: true)
    |> Enum.filter(fn token ->
      case Regex.run(~r/(?:^|:)max-w-(.+)$/, token) do
        [_, size] -> Regex.match?(@container, size)
        nil -> false
      end
    end)
  end
end
