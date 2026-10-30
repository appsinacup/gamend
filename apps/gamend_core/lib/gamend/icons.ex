defmodule Gamend.Icons do
  @moduledoc """
  The site's own icons, which people may pick instead of uploading an image:
  a group's icon, an account's avatar. Every heroicon, by name
  (`rocket-launch`): heroicons.com's 24px solid set, read from the host's
  `heroicons` dependency when this compiles, the same set the website draws
  (`GamendWeb.Icons`).

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

  @doc false
  # Where the set was read from, nil when the host has no heroicons; the
  # website embeds its SVGs from there.
  @spec dir() :: Path.t() | nil
  def dir, do: @dir

  @doc "Every icon's name, sorted: `academic-cap`, …"
  @spec names() :: [String.t()]
  def names, do: @names

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

  @doc "An icon at random, nil when there are none."
  @spec random() :: String.t() | nil
  if @names == [] do
    def random, do: nil
  else
    def random, do: Enum.random(@names)
  end
end
