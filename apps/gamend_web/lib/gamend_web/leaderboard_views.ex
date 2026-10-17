defmodule GamendWeb.LeaderboardViews do
  @moduledoc """
  A board's views on `/leaderboards/<slug>`: tabs and filters, each picking
  one of the board's keys (`Gamend.Leaderboards`, *Keys*).

  A board declares them in its metadata:

      "views" => %{
        "tabs" => ["match", "hangman"],
        "filters" => [%{"field" => "lang", "key" => true}]
      }

    * **A tab is a key.** The first is the one a bare URL opens.
    * **A key filter is a key part.** Picking `es_es` on the `match` tab
      reads key `match|es_es`, so a filtered view is still one key: cached
      by core, ranked within itself. Filters compose in order
      (`tab|first|second`); a filter offers its values once the ones before
      it are picked. Its values are the keys the board holds
      (`Leaderboards.list_keys/2`), so a language nobody has played is not
      offered.
    * **A filter left on "All"** shows each row's value beside its name,
      from the record's `metadata[field]` (a run's language on the game's
      key).

  Only key filters exist so far; a filter without `"key" => true` is
  ignored. The URL holds the view: `?tab=match&lang=es_es`.

  ## Naming things

  Core knows keys and fields, not what they mean. A host names them with a
  module of these callbacks, every one optional, each answering nil to keep
  core's default (the raw key, value or field):

      config :gamend_web, :leaderboard_views, MyHost.LeaderboardViews

  Answers are already in the reader's language: the callbacks run in the
  page's process, with its locale set.
  """

  alias Gamend.Leaderboards
  alias Gamend.Leaderboards.Leaderboard

  @doc "A tab's name (`\"Word match\"`)."
  @callback tab_label(Leaderboard.t(), key :: String.t()) :: String.t() | nil
  @doc "A tab's icon (`\"hero-rectangle-group-solid\"`)."
  @callback tab_icon(Leaderboard.t(), key :: String.t()) :: String.t() | nil
  @doc "A filter's name (`\"Language\"`)."
  @callback filter_label(Leaderboard.t(), field :: String.t()) :: String.t() | nil
  @doc "A filter value's name (`\"Spanish\"` for `es_es`)."
  @callback value_label(Leaderboard.t(), field :: String.t(), value :: String.t()) ::
              String.t() | nil

  @optional_callbacks tab_label: 2, tab_icon: 2, filter_label: 2, value_label: 3

  @typedoc "A board's declared views: its tabs (keys) and its key filters' fields."
  @type t :: %{tabs: [String.t()], filters: [String.t()]}

  @doc """
  The views a board declares, or nil for a board with one ranking (no
  `views`, or no tab in it). Anything malformed is dropped, never raised: a
  bad metadata row shows the plain board.
  """
  @spec of(Leaderboard.t()) :: t() | nil
  def of(%Leaderboard{metadata: %{"views" => %{"tabs" => tabs} = views}}) when is_list(tabs) do
    tabs = Enum.filter(tabs, &(is_binary(&1) and &1 != ""))

    filters =
      for %{"field" => field, "key" => true} <- List.wrap(views["filters"]),
          is_binary(field) and field != "",
          do: field

    if tabs == [], do: nil, else: %{tabs: Enum.uniq(tabs), filters: Enum.uniq(filters)}
  end

  def of(_leaderboard), do: nil

  @doc """
  The view a URL asks for, kept to what the board holds: `{tab, picked}`,
  `picked` the key filters' values in order up to the first one left on All
  (or not offered). An unknown tab is the first tab.
  """
  @spec pick(Leaderboard.t(), t(), map()) :: {String.t(), [{String.t(), String.t()}]}
  def pick(%Leaderboard{} = board, %{tabs: tabs, filters: filters}, params) do
    tab = if params["tab"] in tabs, do: params["tab"], else: hd(tabs)

    # Built in reverse, newest first, and turned round at the end.
    picked =
      filters
      |> Enum.reduce_while([], fn field, reversed ->
        value = params[field]

        if is_binary(value) and value in values(board, tab, Enum.reverse(reversed)),
          do: {:cont, [{field, value} | reversed]},
          else: {:halt, reversed}
      end)
      |> Enum.reverse()

    {tab, picked}
  end

  @doc "The key a view reads: the tab, then the picked values, `|`-joined."
  @spec key(String.t(), [{String.t(), String.t()}]) :: String.t()
  def key(tab, picked), do: Enum.join([tab | Enum.map(picked, &elem(&1, 1))], "|")

  @doc """
  The values a filter offers after `picked`: the next part of every key the
  board holds under `tab|picked…|`, in key order (the page sorts them by
  their names).
  """
  @spec values(Leaderboard.t(), String.t(), [{String.t(), String.t()}]) :: [String.t()]
  def values(%Leaderboard{id: id}, tab, picked) do
    prefix = key(tab, picked) <> "|"

    id
    |> Leaderboards.list_keys(prefix: prefix)
    |> Enum.map(fn k -> k |> String.replace_prefix(prefix, "") |> String.split("|") |> hd() end)
    |> Enum.uniq()
  end

  @doc "A tab's name: the host's, else the key."
  @spec tab_label(Leaderboard.t(), String.t()) :: String.t()
  def tab_label(board, key), do: ask(:tab_label, [board, key]) || key

  @doc "A tab's icon, the host's, else nil."
  @spec tab_icon(Leaderboard.t(), String.t()) :: String.t() | nil
  def tab_icon(board, key), do: ask(:tab_icon, [board, key])

  @doc "A filter's name: the host's, else the field."
  @spec filter_label(Leaderboard.t(), String.t()) :: String.t()
  def filter_label(board, field), do: ask(:filter_label, [board, field]) || field

  @doc "A value's name: the host's, else the value."
  @spec value_label(Leaderboard.t(), String.t(), String.t()) :: String.t()
  def value_label(board, field, value), do: ask(:value_label, [board, field, value]) || value

  # The host's answer when it has the callback and answers a string.
  defp ask(fun, args) do
    with mod when is_atom(mod) and not is_nil(mod) <-
           Application.get_env(:gamend_web, :leaderboard_views),
         true <- Code.ensure_loaded?(mod) and function_exported?(mod, fun, length(args)),
         label when is_binary(label) and label != "" <- apply(mod, fun, args) do
      label
    else
      _ -> nil
    end
  end
end
