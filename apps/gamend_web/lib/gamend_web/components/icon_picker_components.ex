defmodule GamendWeb.IconPickerComponents do
  @moduledoc """
  The pick of one of the site's icons, and its colour, for a URL field. Out of
  `GamendWeb.CoreComponents`, so an edit here recompiles only the forms that
  draw it; imported through `html_helpers`.
  """
  use Phoenix.Component
  use Gettext, backend: GamendWeb.Gettext

  import GamendWeb.CoreComponents, only: [icon: 1, translate_error: 1]

  alias Phoenix.Component

  @doc """
  A pick of one of the site's icons (`Gamend.Icons.picks/0`) for a URL field:
  a group's `icon_url`, an account's `profile_url`. A radio each, whose value
  is the icon's URL (`/icons/<name>.svg`), so a pick is stored as any other
  icon URL is. A grid of whole rows, its columns by the room it has. An icon
  stored from outside the list stays as it is, with no tile lit, until another
  is picked. Each is a `<use>` of the icon sprite
  (`GamendWeb.Icons.sprite_path/0`), which the browser fetches once and keeps,
  so the page carries a few bytes an icon, not its SVG.

  Under it, always, the colour: none, or one of the site's
  (`Gamend.Icons.colors/0`), the tiles drawn in it. With no icon picked yet one
  is already chosen, as good as at random and the same for this form on every
  render, so the icon clicked next comes coloured. The colour is a field of
  its own, `<name>_color` (`group[icon_url_color]`), which the page puts on
  the URL before it casts it: `Gamend.Icons.put_color(params, "icon_url")`.

      <.icon_picker field={@form[:icon_url]} label={gettext("Icon")} />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, default: nil
  attr :on_pick, :any, default: nil, doc: "a `JS` command an icon's click also runs"

  def icon_picker(assigns) do
    field = assigns.field
    value = to_string(field.value)
    errors = if Component.used_input?(field), do: field.errors, else: []
    picked = Gamend.Icons.name(value)
    color = if picked, do: Gamend.Icons.color(value), else: next_color(field, value)
    css = Gamend.Icons.color_css(color)

    assigns =
      assign(assigns,
        names: Gamend.Icons.picks(),
        value: value,
        picked: picked,
        color: color,
        colors: Enum.map(Gamend.Icons.colors(), &{&1, Gamend.Icons.color_css(&1)}),
        color_name: color_field_name(field.name),
        pick_style: css && "--icon-pick: #{css}",
        sprite: GamendWeb.Icons.sprite_path(),
        errors: Enum.map(errors, &translate_error/1)
      )

    # Keyed, so a pick re-sends the two tiles that changed, not all of them.
    ~H"""
    <fieldset :if={@names != []} id={@field.id} class="fieldset mb-2">
      <legend :if={@label} class="label mb-1">{@label}</legend>
      <div class="@container" style={@pick_style}>
        <div class="grid grid-cols-5 gap-1.5 @sm:grid-cols-6 @lg:grid-cols-10 @3xl:grid-cols-15">
          <label :for={name <- @names} :key={name} class="cursor-pointer" title={name}>
            <input
              type="radio"
              name={@field.name}
              value={Gamend.Icons.path(name)}
              checked={@picked == name}
              phx-click={@on_pick}
              aria-label={String.replace(name, "-", " ")}
              class="peer sr-only"
            />
            <span class={[
              "flex aspect-square items-center justify-center rounded-field border border-base-300",
              "transition-colors hover:bg-base-300",
              "peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-primary",
              if(@color,
                do:
                  "text-(--icon-pick) peer-checked:border-(--icon-pick) peer-checked:bg-[color-mix(in_oklab,var(--icon-pick)_20%,var(--color-base-100))]",
                else:
                  "text-muted peer-checked:border-primary peer-checked:bg-primary peer-checked:text-primary-content"
              )
            ]}>
              <svg class="aspect-square w-1/2" fill="currentColor" aria-hidden="true">
                <use href={@sprite <> "#" <> name} />
              </svg>
            </span>
          </label>
        </div>
      </div>
      <%!-- The icon's colour: none, or one of the site's. --%>
      <div
        :if={@colors != []}
        role="radiogroup"
        aria-label={gettext("Color")}
        class="mt-2 flex flex-wrap items-center gap-2"
      >
        <span class="label text-xs">{gettext("Color")}</span>
        <label class="cursor-pointer" title={gettext("No color")}>
          <input
            type="radio"
            name={@color_name}
            value=""
            checked={is_nil(@color)}
            aria-label={gettext("No color")}
            class="peer sr-only"
          />
          <span class={[
            "flex size-7 items-center justify-center rounded-full border border-base-300 bg-base-300 text-muted",
            "peer-checked:ring-2 peer-checked:ring-base-content peer-checked:ring-offset-2 peer-checked:ring-offset-base-100",
            "peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-primary"
          ]}>
            <.icon name="hero-no-symbol-solid" class="size-4" />
          </span>
        </label>
        <label
          :for={{{name, css}, i} <- Enum.with_index(@colors, 1)}
          :key={name}
          class="cursor-pointer"
          title={gettext("Color %{number}", number: i)}
        >
          <input
            type="radio"
            name={@color_name}
            value={name}
            checked={@color == name}
            aria-label={gettext("Color %{number}", number: i)}
            class="peer sr-only"
          />
          <span
            style={"background-color: #{css}"}
            class={[
              "block size-7 rounded-full",
              "peer-checked:ring-2 peer-checked:ring-base-content peer-checked:ring-offset-2 peer-checked:ring-offset-base-100",
              "peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-primary"
            ]}
          />
        </label>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  # With no icon picked, the colour the next one will have: the one chosen so
  # far (`Gamend.Icons.put_color/2` leaves it on the form), "" being none, else
  # one for this form, the same on every render.
  defp next_color(field, value) do
    chosen = field.form.params[to_string(field.field) <> "_color"]

    cond do
      chosen == "" -> nil
      Gamend.Icons.color?(chosen) -> chosen
      true -> Gamend.Icons.color_for({field.id, Map.get(field.form.data, :id), value})
    end
  end

  # The colour's field beside an icon's: `group[icon_url]` → `group[icon_url_color]`.
  defp color_field_name(name) do
    if String.ends_with?(name, "]"),
      do: String.replace_suffix(name, "]", "_color]"),
      else: name <> "_color"
  end

  # `GamendWeb.CoreComponents`' own, private there: a field's error under it.
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle-solid" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end
end
