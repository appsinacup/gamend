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
    * **Each row names its value for every filter** on the line under its
      name: a picked filter's is the view's, one left on "All" the record's
      `metadata[field]` (a run's language on the game's key).

  Only key filters exist so far; a filter without `"key" => true` is
  ignored. The URL holds the view: `?tab=match&lang=es_es`.

  On a board with an all-time ranking (`Leaderboards.all_time?/1`), the
  page reads the view all time with `?period=all`: the same keys, every
  season's (`all_time: true` on `pick/4` and `values/4`).

  ## Naming things

  Core knows keys and fields, not what they mean. A host names them with a
  module of these callbacks, every one optional, each answering nil to keep
  core's default (the raw key, value or field; no badge; the person icon on
  a label row, where `row_avatar/2` draws whatever the host puts there). A row's badge
  marks a row for what it is (`row_badge/2`: a made-up runner, say), first
  on the line under its name (`GamendWeb.CoreComponents.player_card/1`),
  before its filters' values:

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
  @doc "A row's mark, under its name (`\"Crew ghost\"` for a made-up runner), or nil."
  @callback row_badge(Leaderboard.t(), Gamend.Leaderboards.Record.t()) :: String.t() | nil
  @doc """
  What stands where a player's avatar does on a row with no account (a label
  row): any markup the host draws, sized by the avatar's box (its font size
  is the box's, so a `1em` mark fills it); nil for the person icon. Core
  knows nothing of what it is: a picture, an icon, a flag.
  """
  @callback row_avatar(Leaderboard.t(), Gamend.Leaderboards.Record.t()) ::
              Phoenix.LiveView.Rendered.t() | nil

  @optional_callbacks tab_label: 2,
                      tab_icon: 2,
                      filter_label: 2,
                      value_label: 3,
                      row_badge: 2,
                      row_avatar: 2

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
  (or not offered). An unknown tab is the first tab. `all_time: true` keeps
  the values any season holds.
  """
  @spec pick(Leaderboard.t(), t(), map(), keyword()) ::
          {String.t(), [{String.t(), String.t()}]}
  def pick(%Leaderboard{} = board, %{tabs: tabs, filters: filters}, params, opts \\ []) do
    tab = if params["tab"] in tabs, do: params["tab"], else: hd(tabs)

    # Built in reverse, newest first, and turned round at the end.
    picked =
      filters
      |> Enum.reduce_while([], fn field, reversed ->
        value = params[field]

        if is_binary(value) and value in values(board, tab, Enum.reverse(reversed), opts),
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
  their names). `all_time: true` reads every season's keys.
  """
  @spec values(Leaderboard.t(), String.t(), [{String.t(), String.t()}], keyword()) ::
          [String.t()]
  def values(%Leaderboard{id: id}, tab, picked, opts \\ []) do
    prefix = key(tab, picked) <> "|"

    id
    |> Leaderboards.list_keys(prefix: prefix, all_time: Keyword.get(opts, :all_time, false))
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

  @doc "A row's badge: the host's, else none."
  @spec row_badge(Leaderboard.t(), map()) :: String.t() | nil
  def row_badge(board, record), do: ask(:row_badge, [board, record])

  @doc "A label row's avatar: the host's, else none (a row with a user has its own)."
  @spec row_avatar(Leaderboard.t(), map()) :: Phoenix.LiveView.Rendered.t() | nil
  def row_avatar(_board, %{user_id: user_id}) when is_binary(user_id), do: nil
  def row_avatar(board, record), do: host(:row_avatar, [board, record])

  @doc "A value's name: the host's, else the value."
  @spec value_label(Leaderboard.t(), String.t(), String.t()) :: String.t()
  def value_label(board, field, value), do: ask(:value_label, [board, field, value]) || value

  # The host's answer when it has the callback and answers a string.
  defp ask(fun, args) do
    case host(fun, args) do
      label when is_binary(label) and label != "" -> label
      _ -> nil
    end
  end

  # The host's answer as it is (a label, markup), or nil where it has none.
  defp host(fun, args) do
    with mod when is_atom(mod) and not is_nil(mod) <-
           Application.get_env(:gamend_web, :leaderboard_views),
         true <- Code.ensure_loaded?(mod) and function_exported?(mod, fun, length(args)) do
      apply(mod, fun, args)
    else
      _ -> nil
    end
  end
end
