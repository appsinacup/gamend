defmodule GamendWeb.MarkdownComponents do
  @moduledoc """
  Rendered markdown and the colours of its code. Out of
  `GamendWeb.CoreComponents`, so an edit here recompiles only the pages that
  draw it; imported through `html_helpers`.
  """
  use Phoenix.Component

  @div "div"

  @markdown_code_css_path Path.join(__DIR__, "markdown_code.css")
  @external_resource @markdown_code_css_path
  @markdown_code_css @markdown_code_css_path
                     |> File.read!()
                     |> then(&Regex.replace(~r{/\*.*?\*/}s, &1, ""))
                     |> String.trim()

  @doc """
  A block of rendered markdown: the `.markdown-content` a host's stylesheet lays
  out, and the colours of its code, which every host gets from here
  (`markdown_code.css`). In the page and not in a stylesheet because a host's
  build is where they went missing, and only a page with markdown pays for them.

  `html` is what `Gamend.Content` rendered, already sanitised.
  """
  attr :html, :string, default: nil, doc: "sanitised HTML from `Gamend.Content`"
  attr :tag, :string, default: @div
  attr :class, :string, default: nil
  attr :rest, :global

  def markdown(assigns) do
    assigns = assign(assigns, :code_css, @markdown_code_css)

    ~H"""
    <style>
      <%= Phoenix.HTML.raw(@code_css) %>
    </style>
    <.dynamic_tag tag_name={@tag} class={["markdown-content", @class]} {@rest}>
      {Phoenix.HTML.raw(@html)}
    </.dynamic_tag>
    """
  end
end
