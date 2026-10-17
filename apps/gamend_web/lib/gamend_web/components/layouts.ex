defmodule GamendWeb.Layouts do
  @moduledoc """
  Compatibility facade for the host-owned layout shell.
  """

  use GamendWeb, :html

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: nil, doc: "current request path for nav active state"

  attr :flush, :boolean,
    default: false,
    doc: "when true, render content edge-to-edge with no main wrapper, padding, or footer"

  attr :wide, :boolean,
    default: false,
    doc:
      "when true, the content column widens past the reading width — for a page with its own side columns, such as a docs sidebar and table of contents"

  attr :background_icons, :any,
    default: nil,
    doc:
      "pass `false` when the page paints its own decorative icon layer, as `GamendWeb.PresentationPage` does — otherwise the shell adds a second one on top"

  attr :nav_key, :any,
    default: nil,
    doc:
      "a value the navbar shows that the page itself changes, such as a coin balance a `{Module.fun}` nav label reads: the navbar re-renders when it moves. Without it the navbar keeps what it showed at the first render"

  slot :inner_block, required: true

  def app(assigns) do
    host_layouts = host_layouts()
    host_layouts.app(assigns)
  end

  def root(assigns) do
    host_layouts = host_layouts()
    host_layouts.root(assigns)
  end

  def resolve_theme(locale \\ nil, assigned_theme \\ %{}) do
    host_layouts = host_layouts()
    host_layouts.resolve_theme(locale, assigned_theme)
  end

  def home_banner_link do
    host_layouts = host_layouts()
    host_layouts.home_banner_link()
  end

  def icon_placements(icons) do
    host_layouts = host_layouts()
    host_layouts.icon_placements(icons)
  end

  def locale_labels do
    host_layouts = host_layouts()
    host_layouts.locale_labels()
  end

  def strip_locale_prefix(path, known_locales) do
    host_layouts = host_layouts()
    host_layouts.strip_locale_prefix(path, known_locales)
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    host_layouts = host_layouts()
    host_layouts.flash_group(assigns)
  end

  def theme_toggle(assigns) do
    host_layouts = host_layouts()
    host_layouts.theme_toggle(assigns)
  end

  defp host_layouts, do: Module.concat([GamendWeb, HostLayouts])
end
