defmodule GamendWeb.Icons do
  @moduledoc """
  The typed icon set: every heroicon the site ships, as an atom.

  Generated at compile time from `deps/heroicons` (24px solid set), so the
  atoms *are* the icon catalog — `:trophy`, `:currency_dollar`,
  `:academic_cap`, … all #{"324"} of them. Anything choosing an icon in code
  does it through a typed value; an unknown atom raises instead of silently
  rendering nothing.

  `svg/1` returns the icon's inline SVG (compile-time embedded), which is how
  `<.entity_icon>` renders fallbacks — deliberately not the `hero-*` CSS
  classes, because Tailwind only generates those for names it finds literally
  in source, and these names are chosen at runtime.

  Entities with no uploaded `icon_url` fall back to `default/1` for their
  type: every group without an icon shares one icon, every tournament
  another, and so on. API clients get `icon_url` as `null` and apply their
  own equivalent.
  """

  # heroicons is declared by the HOST app, not by gamend_web (it is a
  # GitHub-only dep, unpublishable from a Hex package). Core finds it, and
  # names what people pick from it (`Gamend.Icons`); the SVGs are embedded
  # here, from the same directory.
  @icons_dir Gamend.Icons.dir()

  unless @icons_dir do
    raise """
    heroicons not found in any deps directory.
    The host app must declare it (see apps/gamend_web/mix.exs), run mix deps.get,
    then mix deps.compile gamend_core --force.
    """
  end

  @svgs (for path <- Path.wildcard(Path.join(@icons_dir, "*.svg")), into: %{} do
           name = Path.basename(path, ".svg")
           {name |> String.replace("-", "_") |> String.to_atom(), File.read!(path)}
         end)

  for path <- Path.wildcard(Path.join(@icons_dir, "*.svg")) do
    @external_resource path
  end

  if map_size(@svgs) == 0, do: raise("no heroicons found under #{@icons_dir}")

  # Every icon as a `<symbol>` of one file, for a page that draws many at
  # once (`<.icon_picker>`): each is then a `<use>` of a few bytes, and the
  # file is fetched once and cached for good, its version in its URL.
  @sprite [
            ~s(<svg xmlns="http://www.w3.org/2000/svg">),
            for {icon, svg} <- Enum.sort(@svgs) do
              [_open, body] = String.split(svg, ">", parts: 2)
              inner = body |> String.trim() |> String.replace_suffix("</svg>", "")

              [
                ~s(<symbol id="),
                icon |> Atom.to_string() |> String.replace("_", "-"),
                ~s(" viewBox="0 0 24 24">),
                inner,
                "</symbol>"
              ]
            end,
            "</svg>"
          ]
          |> IO.iodata_to_binary()

  @sprite_path "/icons/sprite.svg?v=" <>
                 (:crypto.hash(:sha256, @sprite)
                  |> Base.url_encode64(padding: false)
                  |> binary_part(0, 12))

  @defaults %{
    group: :user_group,
    tournament: :bolt,
    leaderboard: :chart_bar,
    quest: :trophy,
    notification: :bell,
    user: :user_circle
  }

  for {_type, icon} <- @defaults, not is_map_key(@svgs, icon) do
    raise "default icon #{inspect(icon)} is not in the heroicons set"
  end

  @type icon :: atom()
  @type entity :: unquote(@defaults |> Map.keys() |> Enum.reduce(&{:|, [], [&1, &2]}))

  @doc "The `hero-*` class name for a typed icon atom. Raises on unknown atoms."
  @spec get(icon()) :: String.t()
  def get(icon) when is_map_key(@svgs, icon) do
    "hero-" <> String.replace(Atom.to_string(icon), "_", "-") <> "-solid"
  end

  @doc "Every icon as a `<symbol>` with its name for id (`rocket-launch`), in one SVG."
  @spec sprite() :: String.t()
  def sprite, do: @sprite

  @doc """
  The sprite's URL, versioned by its content so it is cached forever:
  `<svg><use href={sprite_path() <> "#rocket-launch"} /></svg>`.
  """
  @spec sprite_path() :: String.t()
  def sprite_path, do: @sprite_path

  @doc "The icon's raw inline SVG (24px solid, `currentColor` fill)."
  @spec svg(icon()) :: String.t()
  def svg(icon) when is_map_key(@svgs, icon), do: @svgs[icon]

  @doc "The shared default icon atom for an entity type without an icon."
  @spec default(entity()) :: icon()
  def default(type) when is_map_key(@defaults, type), do: @defaults[type]

  @doc "Every typed icon atom, for pickers and docs."
  @spec list() :: [icon()]
  def list, do: @svgs |> Map.keys() |> Enum.sort()

  @doc """
  The URL an icon is served at, for storing in an entity's `icon_url`.

      iex> GamendWeb.Icons.path(:trophy)
      "/icons/trophy.svg"

  Storing a URL rather than an atom keeps `icon_url` one kind of thing: a game
  client fetches it like any other icon, while the web UI recognises its own
  route and inlines the SVG instead (see `GamendWeb.CoreComponents.entity_icon/1`),
  so `currentColor` still follows the theme.
  """
  @spec path(icon()) :: String.t()
  def path(icon) when is_map_key(@svgs, icon), do: "/icons/" <> dasherize(icon) <> ".svg"

  @doc """
  The icon a `path/1` URL refers to, or `:error` for anything else — an
  uploaded image, a CDN URL, a name we do not ship.
  """
  @spec from_path(String.t()) :: {:ok, icon()} | :error
  def from_path("/icons/" <> file) do
    with true <- String.ends_with?(file, ".svg"),
         name <- file |> String.replace_suffix(".svg", "") |> String.replace("-", "_"),
         # `to_existing_atom` keeps an arbitrary URL from creating atoms.
         {:ok, icon} <- safe_atom(name),
         true <- is_map_key(@svgs, icon) do
      {:ok, icon}
    else
      _ -> :error
    end
  end

  def from_path(_url), do: :error

  defp safe_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp dasherize(icon), do: icon |> Atom.to_string() |> String.replace("_", "-")
end
