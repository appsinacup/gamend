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

  @doc "The URL of an icon by name: `/icons/<name>.svg`."
  @spec path(String.t()) :: String.t()
  def path(name) when is_binary(name), do: "/icons/" <> name <> ".svg"

  @doc "The name of the icon a URL is (`path/1`), or nil (none, an upload)."
  @spec name(String.t() | nil) :: String.t() | nil
  def name("/icons/" <> file) do
    name = String.replace_suffix(file, ".svg", "")
    if name?(name), do: name
  end

  def name(_url), do: nil

  @doc "One of `picks/0` at random, nil when there are none."
  @spec random() :: String.t() | nil
  if @picks == [] do
    def random, do: nil
  else
    def random, do: Enum.random(@picks)
  end
end
