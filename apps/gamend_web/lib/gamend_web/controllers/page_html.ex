defmodule GamendWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use GamendWeb, :html

  embed_templates "page_html/*"

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :intro
  slot :inner_block, required: true

  @doc "A section of the UI page (`/ui`): a heading, a line on when to use it."
  def ui_section(assigns) do
    ~H"""
    <.panel tag="section" id={@id} class="scroll-mt-24 space-y-5">
      <div class="space-y-1">
        <h2 class="text-xl font-semibold">{@title}</h2>
        <p :if={@intro != []} class="text-sm text-muted">{render_slot(@intro)}</p>
      </div>
      {render_slot(@inner_block)}
    </.panel>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  @doc "A labelled row of specimens inside a `ui_section/1`."
  def ui_row(assigns) do
    ~H"""
    <div class="space-y-2">
      <.eyebrow tag="h3">{@title}</.eyebrow>
      <div class="flex flex-wrap items-end gap-x-6 gap-y-4">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :code, :string, required: true, doc: "the classes that draw it"
  slot :inner_block, required: true

  @doc "One example, captioned with the classes to copy."
  def specimen(assigns) do
    ~H"""
    <figure class="flex flex-col items-start gap-1.5">
      {render_slot(@inner_block)}
      <figcaption class="font-mono text-xs text-muted">{@code}</figcaption>
    </figure>
    """
  end
end
