defmodule GamendWeb.Api.V1.TournamentController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Tournaments
  alias Gamend.Tournaments.Tournament
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    OkResponse,
    TournamentBracketPage,
    TournamentEntryPage,
    TournamentEntryResponse,
    TournamentMatchResponse,
    TournamentPage,
    TournamentResponse,
    TournamentStandingsResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Tournaments"])

  @id_param [
    in: :path,
    schema: %Schema{type: :string},
    required: true,
    description: "Tournament id, or a slug for its current occurrence"
  ]

  operation(:index,
    operation_id: "list_tournaments",
    summary: "List tournaments",
    parameters: [
      state: [in: :query, schema: %Schema{type: :string}, description: "Filter by state"],
      slug: [in: :query, schema: %Schema{type: :string}, description: "Occurrence history"],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [ok: {"Tournaments", "application/json", TournamentPage}]
  )

  def index(conn, params) do
    {page, page_size} = Pagination.params(params)

    opts =
      [page: page, page_size: page_size]
      |> maybe_put(:state, params["state"])
      |> maybe_put(:slug, params["slug"])

    tournaments = Tournaments.list_tournaments(opts)
    total = Tournaments.count_tournaments(Keyword.drop(opts, [:page, :page_size]))

    reply_page(conn, Enum.map(tournaments, &serialize_tournament/1), page, page_size, total)
  end

  operation(:show,
    operation_id: "get_tournament",
    security: [%{}, %{"authorization" => []}],
    summary: "Tournament details (with the caller's participation when authenticated)",
    parameters: [id: @id_param],
    responses: [
      ok: {"Tournament, with `my_entry`", "application/json", TournamentResponse},
      not_found: Schemas.error("Tournament not found")
    ]
  )

  def show(conn, %{"id" => id}) do
    case fetch_tournament(id) do
      nil ->
        not_found(conn)

      tournament ->
        tournament = Tournaments.advance_lifecycle(tournament)

        entry =
          case current_user(conn) do
            nil -> nil
            user -> Tournaments.get_entry(tournament.id, user.id)
          end

        reply_data(
          conn,
          tournament
          |> serialize_tournament()
          |> Map.put(:my_entry, entry && serialize_entry(entry))
        )
    end
  end

  operation(:join,
    operation_id: "join_tournament",
    summary: "Register as an entry leader",
    description:
      "Answers the new entry. Refusals: `registration_closed`, `tournament_full` or a " <>
        "game hook's `rejected` (403), `already_registered` (409).",
    parameters: [id: @id_param],
    security: [%{"authorization" => []}],
    responses: [
      ok: {"The new entry", "application/json", TournamentEntryResponse},
      forbidden: Schemas.error("Registration closed, full, or rejected by a hook"),
      conflict: Schemas.error("Already registered"),
      not_found: Schemas.error("Tournament not found"),
      unprocessable_entity: Schemas.error("Validation failed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def join(conn, %{"id" => id}) do
    with %Tournament{} = tournament <- fetch_tournament(id),
         {:ok, entry} <- Tournaments.join_tournament(current_user(conn), tournament) do
      reply_data(conn, serialize_entry(entry))
    else
      nil -> not_found(conn)
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:leave,
    operation_id: "leave_tournament",
    summary: "Withdraw the caller's entry (before the draw)",
    description:
      "Refusals: `not_registered` (404), `already_drawn` (409), a game hook's " <>
        "`rejected` (403).",
    parameters: [id: @id_param],
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Left", "application/json", OkResponse},
      forbidden: Schemas.error("Rejected by a hook"),
      conflict: Schemas.error("The draw has happened"),
      not_found: Schemas.error("Tournament not found, or no entry to withdraw"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def leave(conn, %{"id" => id}) do
    with %Tournament{} = tournament <- fetch_tournament(id),
         {:ok, _} <- Tournaments.leave_tournament(current_user(conn), tournament) do
      reply_ok(conn)
    else
      nil -> not_found(conn)
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:standings,
    operation_id: "tournament_standings",
    summary: "Placements, wins and champions",
    parameters: [id: @id_param],
    responses: [
      ok: {"Standings", "application/json", TournamentStandingsResponse},
      not_found: Schemas.error("Tournament not found")
    ]
  )

  def standings(conn, %{"id" => id}) do
    case fetch_tournament(id) do
      nil ->
        not_found(conn)

      tournament ->
        standings = Tournaments.standings(tournament)

        reply_data(conn, %{
          champions: Enum.map(standings.champions, &serialize_entry/1),
          placements: standings.entries
        })
    end
  end

  operation(:entries,
    operation_id: "tournament_entries",
    summary: "Registered entries (paginated)",
    parameters: [
      id: @id_param,
      state: [
        in: :query,
        schema: %Schema{type: :string, enum: ["registered", "active", "eliminated", "winner"]}
      ],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok: {"Entries", "application/json", TournamentEntryPage},
      not_found: Schemas.error("Tournament not found")
    ]
  )

  def entries(conn, %{"id" => id} = params) do
    case fetch_tournament(id) do
      nil ->
        not_found(conn)

      tournament ->
        {page, page_size} = Pagination.params(params)
        state = params["state"]

        entries =
          Tournaments.list_entries(tournament.id,
            page: page,
            page_size: page_size,
            state: state
          )

        total = Tournaments.count_entries(tournament.id, state: state)

        reply_page(conn, Enum.map(entries, &serialize_entry/1), page, page_size, total)
    end
  end

  operation(:bracket,
    operation_id: "tournament_bracket",
    summary: "Brackets and their matches (paginated by bracket)",
    description:
      "A page of brackets, each with its matches and the entries they name. With " <>
        "`index`, a page holding that one bracket.",
    parameters: [
      id: @id_param,
      index: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Return only this bracket"
      ],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 10}]
    ],
    responses: [
      ok: {"Brackets", "application/json", TournamentBracketPage},
      bad_request: Schemas.error("`index` is not an integer (invalid_index)"),
      not_found: Schemas.error("Tournament or bracket not found")
    ]
  )

  def bracket(conn, %{"id" => id} = params) do
    case fetch_tournament(id) do
      nil -> not_found(conn)
      tournament -> render_bracket(conn, tournament, params)
    end
  end

  # An empty `index` is no index, like every other optional query parameter:
  # the Godot SDK sends an unset one as a bare `?index`.
  defp render_bracket(conn, tournament, %{"index" => index} = _params)
       when index not in [nil, ""] do
    with {index, ""} <- Integer.parse(to_string(index)),
         %{} = bracket <- Tournaments.get_bracket(tournament.id, index) do
      reply_page(conn, serialize_brackets(tournament, [bracket]), 1, 1, 1)
    else
      nil -> not_found(conn)
      _ -> reply_error(conn, :bad_request, "invalid_index")
    end
  end

  defp render_bracket(conn, tournament, params) do
    {page, page_size} = Pagination.params(params)
    brackets = Tournaments.list_brackets(tournament.id, page: page, page_size: page_size)
    total = Tournaments.count_brackets(tournament.id)

    reply_page(conn, serialize_brackets(tournament, brackets), page, page_size, total)
  end

  # Each bracket with its own matches, and only the entries those matches
  # name, so a huge field isn't loaded to render one page of brackets.
  defp serialize_brackets(tournament, brackets) do
    matches =
      Tournaments.list_matches(tournament.id, bracket_indexes: Enum.map(brackets, & &1.index))

    entries = match_entries(tournament, matches)
    leaders = Map.new(entries, fn {id, entry} -> {id, entry.leader_id} end)
    by_bracket = Enum.group_by(matches, & &1.bracket_index)

    Enum.map(brackets, fn bracket ->
      bracket_matches = Map.get(by_bracket, bracket.index, [])

      %{
        index: bracket.index,
        size: bracket.size,
        matches: Enum.map(bracket_matches, &serialize_match(&1, leaders)),
        entries:
          bracket_matches
          |> entry_ids()
          |> Enum.map(&(entries |> Map.fetch!(&1) |> serialize_entry()))
      }
    end)
  end

  defp match_entries(tournament, matches),
    do: Tournaments.entries_by_id(tournament.id, entry_ids(matches))

  defp entry_ids(matches) do
    matches
    |> Enum.flat_map(&[&1.a_entry_id, &1.b_entry_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  operation(:my_match,
    operation_id: "tournament_my_match",
    summary: "The caller's current unresolved match",
    description:
      "404 `no_current_match` when the caller has no entry, or no match waiting " <>
        "(between rounds, eliminated, or the tournament is over).",
    parameters: [id: @id_param],
    security: [%{"authorization" => []}],
    responses: [
      ok: {"The match", "application/json", TournamentMatchResponse},
      not_found: Schemas.error("Tournament not found, or no current match"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def my_match(conn, %{"id" => id}) do
    case fetch_tournament(id) do
      nil ->
        not_found(conn)

      tournament ->
        tournament = Tournaments.advance_lifecycle(tournament)

        case Tournaments.my_match(tournament, current_user(conn).id) do
          nil ->
            reply_error(conn, :not_found, "no_current_match")

          match ->
            leaders =
              tournament
              |> match_entries([match])
              |> Map.new(fn {id, entry} -> {id, entry.leader_id} end)

            reply_data(conn, serialize_match(match, leaders))
        end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Accepts a tournament id or a slug (current occurrence).
  defp fetch_tournament(id_or_slug) do
    case Gamend.Parse.uuid(id_or_slug) do
      nil -> Tournaments.get_tournament_by_slug(id_or_slug)
      id -> Tournaments.get_tournament(id)
    end
  end

  defp current_user(conn), do: Scope.user(conn.assigns[:current_scope])

  defp serialize_tournament(%Tournament{} = t) do
    %{
      id: t.id,
      slug: t.slug,
      title: t.title,
      description: t.description || "",
      icon_url: t.icon_url || "",
      state: t.state,
      registration_opens_at: t.registration_opens_at,
      starts_at: t.starts_at,
      ends_at: t.ends_at,
      recur: t.recur || "",
      max_entries: t.max_entries,
      team_size: t.team_size,
      bracket_size: t.bracket_size,
      round_window_sec: t.round_window_sec,
      entry_count: Tournaments.count_entries(t.id),
      metadata: t.metadata || %{}
    }
  end

  defp serialize_entry(entry) do
    %{
      id: entry.id,
      leader_id: entry.leader_id,
      seed: entry.seed,
      bracket_index: entry.bracket_index,
      wins: entry.wins,
      state: entry.state,
      metadata: entry.metadata || %{}
    }
  end

  defp serialize_match(match, leaders), do: Serializers.serialize_tournament_match(match, leaders)

  defp not_found(conn), do: reply_error(conn, :not_found, "not_found")

  # A refusal from `Gamend.Tournaments` is a code; anything else came from a
  # game hook, whose own words are the message.
  defp error(conn, :registration_closed), do: reply_error(conn, :forbidden, "registration_closed")
  defp error(conn, :tournament_full), do: reply_error(conn, :forbidden, "tournament_full")
  defp error(conn, :already_registered), do: reply_error(conn, :conflict, "already_registered")
  defp error(conn, :not_registered), do: reply_error(conn, :not_found, "not_registered")
  defp error(conn, :already_drawn), do: reply_error(conn, :conflict, "already_drawn")
  defp error(conn, :not_found), do: not_found(conn)
  defp error(conn, %Ecto.Changeset{} = changeset), do: unprocessable(conn, changeset)

  defp error(conn, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    reply_error(conn, :forbidden, "rejected", message)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
