defmodule GamendWeb.TextToneTest do
  use ExUnit.Case, async: true

  # Two text tones: `text-base-content`, and `text-muted` for a detail (a
  # `@utility` every host stylesheet declares; the /ui page, "Colours").
  # Templates had grown nine `text-base-content/NN` tones, and under 70%
  # text reads below 4.5:1 on a light theme: `/60` was 4.46 on base-200,
  # the eyebrow's `/55` 3.9 (Lighthouse on Polyglot, 2026-10-08). Hosts
  # carry the same test.
  #
  # A source scan, so a class built from pieces slips past it.
  @roots [Path.expand("../../lib", __DIR__), Path.expand("../../assets/js", __DIR__)]

  test "text is text-base-content or text-muted" do
    offenders =
      for root <- @roots,
          path <- Path.wildcard(root <> "/**/*.{ex,heex,js}"),
          {line, n} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          [_, tone] <- Regex.scan(~r/text-base-content\/(\d+)\b/, line),
          do: "#{Path.relative_to_cwd(path)}:#{n}  text-base-content/#{tone}"

    assert offenders == [],
           """
           A text tone of its own:

           #{Enum.join(offenders, "\n")}

           Use text-muted (a detail) or text-base-content.
           """
  end
end
