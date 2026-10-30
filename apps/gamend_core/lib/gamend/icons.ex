defmodule Gamend.Icons do
  @moduledoc """
  The icons people pick for what is theirs: a group's (`Gamend.Groups`), and
  an account's in place of a picture (`Gamend.Accounts.User`'s
  `avatar_icon`). Heroicon names (`rocket-launch`, heroicons.com's solid
  set), one list for every picker (`choices`).

  A picked icon is stored or answered as its URL, `path/1`
  (`/icons/<name>.svg`): the website serves it and draws it inline
  (`GamendWeb.Icons`, which also draws a leaderboard's, a tournament's or a
  quest's `icon_url` of that form), and a client fetches it against the
  server's address like an uploaded image.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :icons,
    label: "Icons"

  # The `choices` setting's: heroicons that read as a team, a game, a hobby
  # or a person.
  @default_choices ~w(
    rocket-launch trophy fire bolt star heart puzzle-piece sparkles beaker cube
    globe-alt moon sun shield-check musical-note camera paint-brush light-bulb
    flag map cake gift bug-ant cpu-chip command-line code-bracket academic-cap
    briefcase home user-group face-smile film book-open chat-bubble-left-right
    server-stack wrench-screwdriver key cloud megaphone paper-airplane
  )

  @name ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/

  setting(:choices, :list,
    default: @default_choices,
    doc:
      "The icons people pick from, for a group and for an account with no picture: heroicon names (`rocket-launch`, from heroicons.com's solid set). A new group not given one gets one of them at random. Empty: no icons to pick."
  )

  @doc "The icons to pick from (`choices`), heroicon names."
  @spec choices() :: [String.t()]
  def choices do
    Gamend.Settings.get(__MODULE__, :choices)
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and Regex.match?(@name, &1)))
  end

  @doc "Whether `name` is one of `choices/0`."
  @spec choice?(term()) :: boolean()
  def choice?(name), do: is_binary(name) and name in choices()

  @doc "The URL of an icon by name: `/icons/<name>.svg`."
  @spec path(String.t()) :: String.t()
  def path(name) when is_binary(name), do: "/icons/" <> name <> ".svg"

  @doc "The name of one of `choices/0` a URL is (`path/1`), or nil (none, an upload)."
  @spec name(String.t() | nil) :: String.t() | nil
  def name("/icons/" <> file) do
    name = String.replace_suffix(file, ".svg", "")
    if choice?(name), do: name
  end

  def name(_url), do: nil

  @doc "One of `choices/0` at random, nil when there are none."
  @spec random() :: String.t() | nil
  def random do
    case choices() do
      [] -> nil
      choices -> Enum.random(choices)
    end
  end
end
