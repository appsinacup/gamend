defmodule Gamend.Rating do
  @moduledoc """
  Skill ratings, computed: Elo and Glicko-2, for two players, teams and
  free-for-alls, and the gap a matcher accepts as a player waits
  (priv/docs/40-gameplay/32-ratings.md).

      teams = [[Rating.new()], [Rating.new()]]
      [[winner], [loser]] = Rating.settle(teams, [1, 2])

  Pure: nothing here reads or writes. A game stores the numbers where it
  likes; `dump/1` and `load/1` turn one into a map and back. The SDK carries a
  copy of this module (`mix gen.sdk`).
  """

  @typedoc """
  A player's skill: `rating`, how unsure it is (`deviation`, shrinks with
  games, grows when idle) and how erratic the player is (`volatility`).
  """
  @type t :: %__MODULE__{rating: float(), deviation: float(), volatility: float()}

  @typedoc "How a game went for a player: 1.0 a win, 0.5 a draw, 0.0 a loss."
  @type score :: number()

  @center 1500.0
  @max_deviation 350.0
  @initial_volatility 0.06

  defstruct rating: @center, deviation: @max_deviation, volatility: @initial_volatility

  @fields [:rating, :deviation, :volatility]

  @default_k 32
  @default_tau 0.5
  @default_band_base 100
  @default_band_per_second 20
  @default_band_max 1_000

  # Glicko-2 works on its own scale; Glickman's paper gives the constant.
  @scale 173.7178
  @convergence 1.0e-6
  @max_iterations 100
  @min_expected 1.0e-12

  @doc "A player's rating, unrated unless `:rating`, `:deviation` or `:volatility` is given."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    fields =
      opts |> Keyword.validate!(@fields) |> Enum.map(fn {field, value} -> {field, value / 1} end)

    struct!(__MODULE__, fields)
  end

  @doc "The chance `a` beats `b`, between 0.0 and 1.0. Takes ratings or plain numbers."
  @spec expected(t() | number(), t() | number()) :: float()
  def expected(a, b), do: 1 / (1 + :math.pow(10, (value(b) - value(a)) / 400))

  defp value(%__MODULE__{rating: rating}), do: rating
  defp value(number) when is_number(number), do: number

  @doc """
  Elo for one game: `{new_a, new_b}` for ratings `a` and `b`, `score` being
  how it went for `a`. `:k` is the most one game can move a rating (32).
  """
  @spec elo(number(), number(), score(), keyword()) :: {float(), float()}
  def elo(a, b, score, opts \\ [])
      when is_number(a) and is_number(b) and is_number(score) and score >= 0 and score <= 1 do
    opts = Keyword.validate!(opts, k: @default_k)
    change = opts[:k] * (score - expected(a, b))
    {a + change, b - change}
  end

  @doc """
  Glicko-2 for one rating period: `player` after `games`, a list of
  `{opponent, score}`. No games means an idle period, and only the deviation
  grows. `:tau` limits how fast volatility moves (0.5; 0.3 to 1.2 is usual).
  """
  @spec glicko2(t(), [{t(), score()}], keyword()) :: t()
  def glicko2(player, games, opts \\ [])

  def glicko2(%__MODULE__{} = player, [], _opts) do
    phi = player.deviation / @scale
    idle = :math.sqrt(phi * phi + player.volatility * player.volatility)
    %{player | deviation: min(@max_deviation, idle * @scale)}
  end

  def glicko2(%__MODULE__{} = player, games, opts) when is_list(games) do
    opts = Keyword.validate!(opts, tau: @default_tau)
    mu = to_mu(player.rating)
    phi = player.deviation / @scale
    outcomes = Enum.map(games, &outcome(&1, mu))

    variance = 1 / Enum.sum(for {g, e, _score} <- outcomes, do: g * g * e * (1 - e))
    improvement = Enum.sum(for {g, e, score} <- outcomes, do: g * (score - e))

    volatility =
      next_volatility(player.volatility, phi, variance, variance * improvement, opts[:tau])

    pre_period = phi * phi + volatility * volatility
    new_phi = 1 / :math.sqrt(1 / pre_period + 1 / variance)

    %__MODULE__{
      rating: (mu + new_phi * new_phi * improvement) * @scale + @center,
      deviation: min(@max_deviation, new_phi * @scale),
      volatility: volatility
    }
  end

  defp to_mu(rating), do: (rating - @center) / @scale

  defp outcome({%__MODULE__{} = opponent, score}, mu) when score >= 0 and score <= 1 do
    phi = opponent.deviation / @scale
    g = 1 / :math.sqrt(1 + 3 * phi * phi / (:math.pi() * :math.pi()))
    e = 1 / (1 + :math.exp(-g * (mu - to_mu(opponent.rating))))

    # A huge gap rounds to exactly 0 or 1, and the variance would divide by 0.
    {g, e |> max(@min_expected) |> min(1 - @min_expected), score}
  end

  # Step 5 of Glickman's paper: the Illinois method finds the new volatility.
  defp next_volatility(sigma, phi, variance, delta, tau) do
    a = :math.log(sigma * sigma)
    gap = delta * delta - phi * phi - variance

    f = fn x ->
      exp = :math.exp(x)
      total = phi * phi + variance + exp
      exp * (gap - exp) / (2 * total * total) - (x - a) / (tau * tau)
    end

    b = if gap > 0, do: :math.log(gap), else: step_below(f, a, tau, 1)
    :math.exp(illinois(f, a, b, f.(a), f.(b), @max_iterations) / 2)
  end

  defp step_below(f, a, tau, k) do
    candidate = a - k * tau

    if k < @max_iterations and f.(candidate) < 0,
      do: step_below(f, a, tau, k + 1),
      else: candidate
  end

  defp illinois(_f, a, _b, _fa, _fb, 0), do: a
  defp illinois(_f, a, b, fa, fb, _left) when abs(b - a) <= @convergence or fa == fb, do: a

  defp illinois(f, a, b, fa, fb, left) do
    c = a + (a - b) * fa / (fb - fa)
    fc = f.(c)

    if fc * fb <= 0,
      do: illinois(f, b, c, fb, fc, left - 1),
      else: illinois(f, a, c, fa / 2, fc, left - 1)
  end

  @doc """
  One finished match of any shape: `teams` (a list of lists of `t/0`, a team
  of one for a duel or a free-for-all) and each team's place in `places`, 1
  the best and equal places a draw. Answers the teams, in order, updated.

  Each player is rated against every other team taken as one opponent.
  `:algorithm` is `:glicko2` (default) or `:elo`, with `:tau` and `:k` as in
  those functions.
  """
  @spec settle([[t()]], [pos_integer()], keyword()) :: [[t()]]
  def settle(teams, places, opts \\ []) when length(teams) == length(places) do
    opts = Keyword.validate!(opts, algorithm: :glicko2, k: @default_k, tau: @default_tau)
    sides = Enum.zip(Enum.map(teams, &composite/1), places)

    teams
    |> Enum.zip(places)
    |> Enum.with_index()
    |> Enum.map(fn {{team, place}, index} ->
      games =
        for {side, other_place} <- List.delete_at(sides, index) do
          {side, score(place, other_place)}
        end

      Enum.map(team, &rate(&1, games, opts))
    end)
  end

  defp score(place, other) when place < other, do: 1.0
  defp score(place, other) when place > other, do: 0.0
  defp score(_place, _other), do: 0.5

  defp rate(player, games, opts) do
    case opts[:algorithm] do
      :glicko2 -> glicko2(player, games, tau: opts[:tau])
      :elo -> elo_against(player, games, opts[:k])
    end
  end

  defp elo_against(player, [], _k), do: player

  defp elo_against(player, games, k) do
    share = k / length(games)

    change =
      Enum.sum(for {opponent, score} <- games, do: share * (score - expected(player, opponent)))

    %{player | rating: player.rating + change}
  end

  defp composite(team) when team != [] do
    count = length(team)

    %__MODULE__{
      rating: Enum.sum_by(team, & &1.rating) / count,
      deviation: :math.sqrt(Enum.sum_by(team, &(&1.deviation * &1.deviation)) / count),
      volatility: Enum.sum_by(team, & &1.volatility) / count
    }
  end

  @doc """
  The rating gap a matcher accepts after waiting `waited_ms`: it starts at
  `:base` (100), grows by `:per_second` (20) and stops at `:max` (1000), so
  nobody waits forever for a perfect opponent.
  """
  @spec band(non_neg_integer(), keyword()) :: number()
  def band(waited_ms, opts \\ []) when is_integer(waited_ms) and waited_ms >= 0 do
    opts =
      Keyword.validate!(opts,
        base: @default_band_base,
        per_second: @default_band_per_second,
        max: @default_band_max
      )

    min(opts[:max], opts[:base] + opts[:per_second] * waited_ms / 1000)
  end

  @doc "A rating as a map of plain values, for KV, metadata or a leaderboard record."
  @spec dump(t()) :: %{String.t() => float()}
  def dump(%__MODULE__{} = rating) do
    Map.new(@fields, &{Atom.to_string(&1), Map.fetch!(rating, &1)})
  end

  @doc "The rating `dump/1` wrote. Nothing stored, or a field that is not a number, is unrated."
  @spec load(map() | nil) :: t()
  def load(nil), do: new()

  def load(%{} = stored) do
    new(
      for field <- @fields,
          value = Map.get(stored, Atom.to_string(field)),
          is_number(value),
          do: {field, value}
    )
  end
end
