defmodule GameServer.Tournaments do
  @moduledoc ~S"""
  Bracket tournaments: registration → seeded single-elimination draw → timed
  rounds → champions. See TOURNAMENT_DESIGN.md.
  
  Core owns the structure (registration, seeding, rounds, deadlines,
  advancement, recurrence). Gameplay and judgment belong to the game: when a
  match becomes playable the `tournament_match_ready` hook fires, the game
  plays it however it wants (a lobby, solo runs, anything) and reports the
  verdict with `resolve_match/2`. Unresolved matches past their deadline_at fire
  `tournament_match_expired` for the game to adjudicate; the tournament's
  `deadline_policy` applies only if it doesn't.
  
  Realtime: entry leaders receive `{:tournament_event, event, payload}` on the
  `"tournaments:user:<user_id>"` PubSub topic (forwarded by the user channel
  as `tournament_*` events).
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the GameServer.
  """



  @doc ~S"""
    Applies any due state transition to one tournament and returns the current
    row. Called lazily from API paths and periodically from `tick/0`.
    
  """
  @spec advance_lifecycle(GameServer.Tournaments.Tournament.t(), DateTime.t()) ::
  GameServer.Tournaments.Tournament.t()
  def advance_lifecycle(_tournament, _now) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.advance_lifecycle/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Rounds needed to win a bracket of `size` slots (2→1, 4→2, 8→3).
  """
  @spec bracket_rounds(pos_integer()) :: pos_integer()
  def bracket_rounds(_size) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.bracket_rounds/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Smallest power of two seating `n` entries, min 2, capped at `max`.
  """
  @spec bracket_size_for(pos_integer(), pos_integer()) :: pos_integer()
  def bracket_size_for(_n, _max) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.bracket_size_for/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Cancels a tournament (terminal, no hooks fired, no recurrence spawn).
  """
  @spec cancel_tournament(GameServer.Tournaments.Tournament.t()) ::
  {:ok, GameServer.Tournaments.Tournament.t()} | {:error, term()}
  def cancel_tournament(_tournament) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.cancel_tournament/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec change_tournament(GameServer.Tournaments.Tournament.t(), map()) :: Ecto.Changeset.t()
  def change_tournament(_tournament, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.change_tournament/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_brackets(Ecto.UUID.t()) :: non_neg_integer()
  def count_brackets(_tournament_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.count_brackets/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Counts entries. Accepts the same `:state` and `:search` options as the listing.
  """
  @spec count_entries(
  Ecto.UUID.t(),
  keyword()
) :: non_neg_integer()
  def count_entries(_tournament_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.count_entries/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Counts distinct tournament slugs.
  """
  @spec count_tournament_groups() :: non_neg_integer()
  def count_tournament_groups() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.count_tournament_groups/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec count_tournaments(keyword()) :: non_neg_integer()
  def count_tournaments(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.count_tournaments/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec create_tournament(map()) ::
  {:ok, GameServer.Tournaments.Tournament.t()} | {:error, Ecto.Changeset.t()}
  def create_tournament(_attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.create_tournament/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec delete_tournament(GameServer.Tournaments.Tournament.t()) ::
  {:ok, GameServer.Tournaments.Tournament.t()} | {:error, term()}
  def delete_tournament(_tournament) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.delete_tournament/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Entries by id, for rendering a bracket without loading the whole field.
  """
  @spec entries_by_id(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{
  required(Ecto.UUID.t()) => GameServer.Tournaments.Entry.t()
}
  def entries_by_id(_tournament_id, _entry_ids) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.entries_by_id/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_bracket(Ecto.UUID.t(), integer()) :: GameServer.Tournaments.Bracket.t() | nil
  def get_bracket(_tournament_id, _index) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Tournaments.Bracket{id: "", tournament_id: "", index: 0, size: 8, inserted_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Tournaments.get_bracket/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_entry(Ecto.UUID.t(), Ecto.UUID.t()) :: GameServer.Tournaments.Entry.t() | nil
  def get_entry(_tournament_id, _leader_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Tournaments.Entry{id: "", tournament_id: "", leader_id: "", seed: nil, bracket_index: nil, wins: 0, state: "registered", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Tournaments.get_entry/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_match(Ecto.UUID.t()) :: GameServer.Tournaments.Match.t() | nil
  def get_match(_match_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Tournaments.Match{id: "", tournament_id: "", bracket_index: 0, round: 1, slot: 0, a_entry_id: nil, b_entry_id: nil, winner_entry_id: nil, ready_at: nil, expired_at: nil, resolved_at: nil, deadline_at: ~U[1970-01-01 00:00:00Z], metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Tournaments.get_match/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_tournament(Ecto.UUID.t()) :: GameServer.Tournaments.Tournament.t() | nil
  def get_tournament(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Tournaments.get_tournament/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec get_tournament!(Ecto.UUID.t()) :: GameServer.Tournaments.Tournament.t()
  def get_tournament!(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.get_tournament!/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The current occurrence for a slug: the latest one that is not finished or
    cancelled, falling back to the most recent row.
    
  """
  @spec get_tournament_by_slug(String.t()) :: GameServer.Tournaments.Tournament.t() | nil
  def get_tournament_by_slug(_slug) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Tournaments.get_tournament_by_slug/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Registers `user` as an entry leader. Runs the `before_tournament_register`
    pipeline (games gate/charge entry there) and fires
    `after_tournament_register` on success.
    
  """
  @spec join_tournament(GameServer.Accounts.User.t(), GameServer.Tournaments.Tournament.t()) ::
  {:ok, GameServer.Tournaments.Entry.t()} | {:error, term()}
  def join_tournament(_user, _tournament) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Entry{id: "", tournament_id: "", leader_id: "", seed: nil, bracket_index: nil, wins: 0, state: "registered", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.join_tournament/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Withdraws `user`'s entry. Only before the draw; `before_tournament_leave` can veto.
  """
  @spec leave_tournament(GameServer.Accounts.User.t(), GameServer.Tournaments.Tournament.t()) ::
  {:ok, GameServer.Tournaments.Tournament.t()} | {:error, term()}
  def leave_tournament(_user, _tournament) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.leave_tournament/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Brackets for a tournament. Options: `:page`, `:page_size`.
  """
  @spec list_brackets(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Tournaments.Bracket.t()]
  def list_brackets(_tournament_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Tournaments.list_brackets/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Entries for a tournament, oldest first (registration order = seed rank).
    
    Options: `:page`, `:page_size` (capped at 100), `:state`, plus
    
      * `:search` — filter by leader name (display name or username)
      * `:preload_leader` — preload the leader, for callers that render names
      * `:order` — `:bracket` groups drawn entries by bracket and seed instead
    
    
  """
  @spec list_entries(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Tournaments.Entry.t()]
  def list_entries(_tournament_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Tournaments.list_entries/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Matches for a tournament, bracket-major order.
    
    Options: `:bracket_index` (single bracket), `:bracket_indexes` (several).
    
  """
  @spec list_matches(
  Ecto.UUID.t(),
  keyword()
) :: [GameServer.Tournaments.Match.t()]
  def list_matches(_tournament_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Tournaments.list_matches/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Every occurrence of a slug, newest first.
  """
  @spec list_occurrences(String.t()) :: [GameServer.Tournaments.Tournament.t()]
  def list_occurrences(_slug) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Tournaments.list_occurrences/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Tournaments grouped by slug — one entry per tournament *type*, the way
    leaderboard seasons are grouped.
    
    Each group carries the newest occurrence's title/description, the id of the
    occurrence to open by default (the live one, else the newest), and how many
    editions exist.
    
  """
  @spec list_tournament_groups(keyword()) :: [map()]
  def list_tournament_groups(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Tournaments.list_tournament_groups/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec list_tournaments(keyword()) :: [GameServer.Tournaments.Tournament.t()]
  def list_tournaments(_opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Tournaments.list_tournaments/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The match a slot reaches in `round` (standard folding).
  """
  @spec match_index(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def match_index(_slot, _round) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.match_index/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The match struct with tournament and both entries preloaded (hook payload).
  """
  @spec match_payload(GameServer.Tournaments.Tournament.t(), GameServer.Tournaments.Match.t()) ::
  GameServer.Tournaments.Match.t()
  def match_payload(_tournament, _match) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.match_payload/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The caller's current unresolved match (their entry filled in a slot), if any.
  """
  @spec my_match(GameServer.Tournaments.Tournament.t(), Ecto.UUID.t()) ::
  GameServer.Tournaments.Match.t() | nil
  def my_match(_tournament, _user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: %GameServer.Tournaments.Match{id: "", tournament_id: "", bracket_index: 0, round: 1, slot: 0, a_entry_id: nil, b_entry_id: nil, winner_entry_id: nil, ready_at: nil, expired_at: nil, resolved_at: nil, deadline_at: ~U[1970-01-01 00:00:00Z], metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}

      _ ->
        raise "GameServer.Tournaments.my_match/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Reopens a cancelled tournament.
    
    A tournament that was never drawn goes back to `registration`; one that
    already has a bracket resumes at `running`, so an accidental cancel does not
    throw away the draw. Any due transition is applied immediately afterwards.
    
  """
  @spec reopen_tournament(GameServer.Tournaments.Tournament.t()) ::
  {:ok, GameServer.Tournaments.Tournament.t()} | {:error, term()}
  def reopen_tournament(_tournament) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.reopen_tournament/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Records the verdict for a match: the winning entry's id, or `:no_winner`
    (double forfeit — the next round's seat stays empty and cascades as a bye).
    
    First write wins; anything later returns `{:error, :already_resolved}`. The
    `before_tournament_result` pipeline can veto, leaving the match open.
    
  """
  @spec resolve_match(Ecto.UUID.t(), Ecto.UUID.t() | :no_winner) ::
  {:ok, GameServer.Tournaments.Match.t()} | {:error, term()}
  def resolve_match(_match_id, _winner) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Match{id: "", tournament_id: "", bracket_index: 0, round: 1, slot: 0, a_entry_id: nil, b_entry_id: nil, winner_entry_id: nil, ready_at: nil, expired_at: nil, resolved_at: nil, deadline_at: ~U[1970-01-01 00:00:00Z], metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.resolve_match/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Unix-independent deadline_at for `round`, anchored to `starts_at`.
  """
  @spec round_deadline(GameServer.Tournaments.Tournament.t(), pos_integer()) :: DateTime.t()
  def round_deadline(_tournament, _round) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.round_deadline/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Matches in `round` of a bracket of `size` slots.
  """
  @spec round_matches(pos_integer(), pos_integer()) :: pos_integer()
  def round_matches(_size, _round) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.round_matches/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    When `round` becomes playable (its window start).
  """
  @spec round_opens_at(GameServer.Tournaments.Tournament.t(), pos_integer()) :: DateTime.t()
  def round_opens_at(_tournament, _round) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.round_opens_at/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Standard single-elimination seeding order for a power-of-two `size`:
    slot `i` holds this seed rank (1-based); top seeds are spread apart.
    
  """
  @spec standard_seed_order(pos_integer()) :: [pos_integer()]
  def standard_seed_order(_size) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Tournaments.standard_seed_order/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Final (or current) placements: champions first, then by wins.
  """
  @spec standings(GameServer.Tournaments.Tournament.t()) :: map()
  def standings(_tournament) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Tournaments.standings/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Aggregate counts for the admin dashboard.
    
    Four grouped/filtered queries, all index-backed (`tournaments.state`,
    `tournament_entries.state`, and the partial `tournament_matches` index on
    open matches).
    
  """
  @spec stats() :: %{
  tournaments: map(),
  entries: map(),
  matches: %{total: non_neg_integer(), open: non_neg_integer(), overdue: non_neg_integer()}
}
  def stats() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Tournaments.stats/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Periodic driver, called by `GameServer.Tournaments.Ticker`. Runs every
    transition, match-ready firing, deadline_at sweep, and recurrence spawn that is
    due. Serialized cluster-wide so hooks fire once.
    
  """
  @spec tick(DateTime.t()) :: :ok
  def tick(_now) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Tournaments.tick/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Deep-merges `map` into the match's metadata (game scratch space).
    
    Serialized per match and merged recursively so concurrent writers touching
    different nested keys (e.g. each player's run under `"runs"`) never clobber
    each other.
    
  """
  @spec update_match_metadata(Ecto.UUID.t(), map()) ::
  {:ok, GameServer.Tournaments.Match.t()} | {:error, term()}
  def update_match_metadata(_match_id, _map) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Match{id: "", tournament_id: "", bracket_index: 0, round: 1, slot: 0, a_entry_id: nil, b_entry_id: nil, winner_entry_id: nil, ready_at: nil, expired_at: nil, resolved_at: nil, deadline_at: ~U[1970-01-01 00:00:00Z], metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.update_match_metadata/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc false
  @spec update_tournament(GameServer.Tournaments.Tournament.t(), map()) ::
  {:ok, GameServer.Tournaments.Tournament.t()} | {:error, Ecto.Changeset.t()}
  def update_tournament(_tournament, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Tournaments.Tournament{id: "", slug: "", title: "", description: "", state: "scheduled", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: "forfeit_both", metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Tournaments.update_tournament/2 is a stub - only available at runtime on GameServer"
    end
  end

end
