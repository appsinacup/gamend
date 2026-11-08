defmodule Gamend.Icons do
  @moduledoc """
  The site's own icons, by name (`rocket-launch`): heroicons.com's 24px solid
  set, read from the host's `heroicons` dependency when this compiles, the same
  set the website draws (`GamendWeb.Icons`).

  People pick from a few of them instead of uploading an image, for a group's
  icon or an account's avatar: `picks/0`. Any other still works where it is
  stored, by an API client or from before there was a list.

  An icon is nothing but a URL, `path/1` (`/icons/<name>.svg`), stored where
  an uploaded image's URL would be (a group's `icon_url`, a user's
  `profile_url`, a leaderboard's or a quest's `icon_url`). The website serves
  it and draws it inline; a client fetches it against the server's address
  like an uploaded image.

  A picked icon may carry one of the site's colours, `path/2`
  (`/icons/<name>.svg?color=<color>`): `colors/0`, the theme's own by default
  (`primary info success warning error`), each a CSS colour the website draws
  the icon in (`color_css/1`). A client reads the name from the URL's `color`
  and tints it its own way; the SVG served is the same. A host picks its own
  colours in Elixir:

      config :gamend_core, Gamend.Icons,
        colors: ["primary", "success", {"rose", "#e11d48"}]

  a bare name being the theme's (`var(--color-<name>)`), a pair any CSS colour.

  Every user has an icon: one they never picked is theirs by their id, an
  icon and a colour (`for_id/1`), the same everywhere they are shown.
  """

  # heroicons is the host's dependency, not this app's (a GitHub-only dep,
  # unpublishable from a Hex package): next to this app's own deps (the
  # host's shared deps dir when compiled as a dependency), else the umbrella's
  # when this app runs standalone, its test suite.
  @dir [
         :ecto |> then(&Mix.Project.deps_paths()[&1]) |> Path.dirname(),
         Path.expand("../../../../deps", __DIR__)
       ]
       |> Enum.map(&Path.join(&1, "heroicons/optimized/24/solid"))
       |> Enum.find(&File.dir?/1)

  @files if @dir, do: Path.wildcard(Path.join(@dir, "*.svg")), else: []

  for path <- @files do
    @external_resource path
  end

  @names @files |> Enum.map(&Path.basename(&1, ".svg")) |> Enum.sort()
  @name_set MapSet.new(@names)

  # What looks good on a round avatar, one of a kind: no arrows, controls or
  # documents, nothing that reads as a badge (`shield-check` as "verified"), a
  # button (`bell`) or a site's own sections (`home`, `map`). 30 fills every row
  # at 5, 6, 10 and 15 columns, the widths `<.icon_picker>` draws.
  @picks if @names == [],
           do: [],
           else: ~w(
             academic-cap beaker bolt book-open bug-ant
             cake cloud cpu-chip cube face-smile
             film fire gift globe-alt heart
             key lifebuoy light-bulb megaphone moon
             musical-note paint-brush paper-airplane puzzle-piece rocket-launch
             star sun ticket trophy wrench
           )

  for name <- @picks, name not in @names do
    raise "icon pick #{inspect(name)} is not in the heroicons set"
  end

  @doc false
  # Where the set was read from, nil when the host has no heroicons; the
  # website embeds its SVGs from there.
  @spec dir() :: Path.t() | nil
  def dir, do: @dir

  @doc "Every icon's name, sorted: `academic-cap`, …"
  @spec names() :: [String.t()]
  def names, do: @names

  @doc "The icons people pick from, `academic-cap`, …: the same order everywhere."
  @spec picks() :: [String.t()]
  def picks, do: @picks

  @doc "Whether `name` is an icon's."
  @spec name?(term()) :: boolean()
  def name?(name), do: is_binary(name) and MapSet.member?(@name_set, name)

  @doc "The URL of an icon by name: `/icons/<name>.svg`, with `color` when one of `colors/0`."
  @spec path(String.t(), String.t() | nil) :: String.t()
  def path(name, color \\ nil) when is_binary(name) do
    if color?(color),
      do: "/icons/" <> name <> ".svg?color=" <> color,
      else: "/icons/" <> name <> ".svg"
  end

  @doc """
  The name of the icon a URL is (`path/1`), or nil (none, an upload). A colour
  on it (`?color=`) is no part of the name, and one the site no longer has
  keeps the icon (drawn in none).
  """
  @spec name(String.t() | nil) :: String.t() | nil
  def name("/icons/" <> rest) do
    with {file, query} <- split_query(rest),
         true <- query_ok?(query),
         name = String.replace_suffix(file, ".svg", ""),
         true <- name?(name) do
      name
    else
      _ -> nil
    end
  end

  def name(_url), do: nil

  @doc "The colour of an icon's URL (`path/2`), one of `colors/0`, or nil."
  @spec color(String.t() | nil) :: String.t() | nil
  def color("/icons/" <> rest) do
    with {_file, "color=" <> color} <- split_query(rest),
         true <- color?(color) do
      color
    else
      _ -> nil
    end
  end

  def color(_url), do: nil

  # `<file>?<query>`: the query, when there is one, `color=<name>` and nothing
  # else, so a stored icon is never an arbitrary URL.
  defp split_query(rest) do
    case String.split(rest, "?", parts: 2) do
      [file] -> {file, nil}
      [file, query] -> {file, query}
    end
  end

  defp query_ok?(nil), do: true
  defp query_ok?("color=" <> color), do: Regex.match?(~r/\A[a-z0-9-]{1,32}\z/, color)
  defp query_ok?(_query), do: false

  @default_colors ~w(primary info success warning error)

  @doc """
  The colours an icon is drawn in, by name, in order: the host's
  (`config :gamend_core, Gamend.Icons, colors: [...]`), else the theme's
  `primary info success warning error`.
  """
  @spec colors() :: [String.t()]
  def colors, do: Enum.map(palette(), &elem(&1, 0))

  @doc "Whether `color` is one of `colors/0`."
  @spec color?(term()) :: boolean()
  def color?(color) when is_binary(color), do: List.keymember?(palette(), color, 0)
  def color?(_color), do: false

  @doc """
  The CSS colour a colour is drawn in: a theme's own name its
  `var(--color-<name>)`, a pair's what it gives. Nil for none of `colors/0`.
  """
  @spec color_css(String.t() | nil) :: String.t() | nil
  def color_css(color) do
    case List.keyfind(palette(), color, 0) do
      {_color, css} -> css
      nil -> nil
    end
  end

  defp palette do
    :gamend_core
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:colors, @default_colors)
    |> Enum.flat_map(fn
      name when is_binary(name) -> [{name, "var(--color-" <> name <> ")"}]
      name when is_atom(name) -> [{Atom.to_string(name), "var(--color-#{name})"}]
      {name, css} when is_binary(css) -> [{to_string(name), css}]
      _other -> []
    end)
  end

  @doc """
  `params` with the colour picked beside an icon (`"<key>_color"`, what
  `<.icon_picker>` sends) put on the icon's URL at `key` (`path/2`), the
  colour's own key gone. An upload's URL stays as it is: a colour is only an
  icon's. With no icon picked the colour's key stays, for the form to draw it
  as the one an icon picked next will have.
  """
  @spec put_color(map(), String.t()) :: map()
  def put_color(params, key) when is_map(params) and is_binary(key) do
    case name(params[key]) do
      nil ->
        params

      name ->
        {color, params} = Map.pop(params, key <> "_color")
        Map.put(params, key, path(name, color || color(params[key])))
    end
  end

  def put_color(params, _key), do: params

  @doc "One of `picks/0` at random, nil when there are none."
  @spec random() :: String.t() | nil
  if @picks == [] do
    def random, do: nil
  else
    def random, do: Enum.random(@picks)
  end

  @doc "The URL of an icon at random in a colour at random (`path/2`), nil when there are none."
  @spec random_path() :: String.t() | nil
  def random_path do
    if name = random(), do: path(name, random_color())
  end

  @doc "One of `colors/0` for `term`: as good as random, the same for it every time. Nil with none."
  @spec color_for(term()) :: String.t() | nil
  def color_for(term) do
    case colors() do
      [] -> nil
      colors -> Enum.at(colors, :erlang.phash2(term, length(colors)))
    end
  end

  defp random_color do
    case colors() do
      [] -> nil
      colors -> Enum.random(colors)
    end
  end

  @doc """
  The icon a user who picked none has, by their `id`: one of `picks/0` in one
  of `colors/0`, the same for that id every time, so it is theirs wherever they
  are shown and in what every API answers. Nil when there are no icons.
  """
  @spec for_id(String.t()) :: String.t() | nil
  if @picks == [] do
    def for_id(_id), do: nil
  else
    def for_id(id) when is_binary(id) do
      name = Enum.at(@picks, :erlang.phash2(id, length(@picks)))
      path(name, color_for({id, :color}))
    end
  end
end
