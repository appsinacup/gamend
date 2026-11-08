defmodule GamendWeb.MarkdownComponentTest do
  @moduledoc """
  `<.markdown>` is how every host's markdown gets the colors of its code, so
  a page that renders through it has them with nothing in the host's CSS.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GamendWeb.CoreComponents

  defp render(assigns), do: render_component(&CoreComponents.markdown/1, assigns)

  test "wraps the HTML in the element a host's stylesheet lays out" do
    html = render(html: "<p>Hi</p>", tag: "article", class: "max-h-96")

    assert html =~ ~s(class="markdown-content max-h-96")
    assert html =~ "<article"
    assert html =~ "<p>Hi</p>"
  end

  test "brings the colors of code in both themes" do
    html = render(html: "<p>Hi</p>")

    assert html =~ ~s(:where(.markdown-content [class*="l-keyword"]))
    assert html =~ ~s(:where([data-theme="dark"] .markdown-content [class*="l-keyword"]))
  end

  # Every selector in `:where()` is what lets a host's own palette win.
  test "no rule outweighs a host's" do
    [_, css] = Regex.run(~r{<style>(.*)</style>}s, render(html: ""))

    selectors = Regex.scan(~r/^[^\s}][^{]*(?=\{)/m, css) |> List.flatten()

    assert selectors != []
    assert Enum.all?(selectors, &String.starts_with?(&1, ":where("))
  end

  test "an empty block is fine" do
    assert render(html: nil) =~ "markdown-content"
  end
end
