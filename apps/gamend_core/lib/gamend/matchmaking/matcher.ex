defmodule Gamend.Matchmaking.Matcher do
  @moduledoc """
  Match-forming logic for a group of tickets that share the same
  `match_params`.

  The unit of matching is not a ticket but a *group*: tickets sharing a
  `party_id` are indivisible, and a solo queuer is a group of one. A match is
  built by packing whole groups, so a party is either seated together or stays
  queued — it is never split across lobbies.

  A match is formed when:
    * the packed groups total at least `min_players`, and
    * the packed groups total exactly `max_players`, or
    * the oldest group has waited at least `timeout_ms`.

  Groups are consumed in FIFO order by their oldest ticket. A single bucket can
  produce multiple matches in one sweep.

  A backfill ticket (`lobby_id`) counts as its lobby's members (`size`), a
  match holds at most one lobby with other players in it, and it fits in that
  lobby's seats (`Gamend.Matchmaking.seatable?/1`).

  Players who have blocked each other are never placed in the same match. The
  blocked set is passed in rather than queried here, so this module stays pure
  and the caller resolves every pair in a single query (see
  `Gamend.Friends.blocked_pairs/1`).
  """

  alias Gamend.Friends
  alias Gamend.Types

  @doc """
  Forms all possible matches from a list of tickets.

  `blocked` is a `MapSet` of order-independent user pairs (as built by
  `Gamend.Friends.blocked_pairs/1`) that must not share a match. Defaults
  to empty, which forms matches on FIFO order alone.

  Returns `{matches, remaining}` where `matches` is a list of ticket lists
  and `remaining` are the tickets that could not be matched yet.
  """
  @spec form_matches([Types.matchmaking_ticket()]) ::
          {[[Types.matchmaking_ticket()]], [Types.matchmaking_ticket()]}
  @spec form_matches([Types.matchmaking_ticket()], MapSet.t()) ::
          {[[Types.matchmaking_ticket()]], [Types.matchmaking_ticket()]}
  def form_matches(tickets, blocked \\ MapSet.new()) do
    {matches, remaining_groups} =
      tickets
      |> group_tickets()
      |> do_form_matches(blocked, [])

    {matches, Enum.flat_map(remaining_groups, & &1)}
  end

  # Tickets of one party become a single group, ordered by the party's oldest
  # ticket so a party keeps the queue position it joined at.
  #
  # Both sorts name `DateTime` explicitly. Without it `sort_by` falls back to
  # Erlang term order, which compares a `DateTime` struct field by field in
  # *alphabetical key* order — `microsecond` before `minute` and `second`. So
  # 10:00:01.999999 sorted *after* 10:00:02.000001, and any two tickets
  # straddling a second boundary came out in reverse queue order: the anchor
  # was whoever queued second, and the player who had waited longest was passed
  # over. Same-second tickets compare correctly, which is why this only ever
  # failed intermittently.
  defp group_tickets(tickets) do
    tickets
    |> Enum.with_index()
    |> Enum.group_by(
      fn {ticket, index} -> ticket.party_id || {:solo, index} end,
      fn {ticket, _index} -> ticket end
    )
    |> Map.values()
    |> Enum.map(&Enum.sort_by(&1, fn ticket -> ticket.queued_at end, DateTime))
    |> Enum.sort_by(fn [oldest | _] -> oldest.queued_at end, DateTime)
  end

  defp do_form_matches([], _blocked, matches), do: {Enum.reverse(matches), []}

  defp do_form_matches(groups, blocked, matches) do
    case find_match(groups, blocked, []) do
      {match, rest} -> do_form_matches(rest, blocked, [match | matches])
      :none -> {Enum.reverse(matches), groups}
    end
  end

  # Tries to build a match anchored at the oldest group. When the anchor cannot
  # fill a match, retries from the next group, so one party that fits nowhere
  # cannot stall everyone behind it.
  defp find_match([], _blocked, _skipped), do: :none

  defp find_match([[anchor | _] = anchor_group | rest], blocked, skipped) do
    min = anchor.min_players
    max = anchor.max_players
    elapsed = DateTime.diff(DateTime.utc_now(), anchor.queued_at, :millisecond)

    {packed, leftover} = pack([anchor_group | rest], blocked, max)
    size = count(packed)

    cond do
      size >= min and (size == max or elapsed >= anchor.timeout_ms) ->
        {Enum.flat_map(packed, & &1), Enum.reverse(skipped) ++ leftover}

      # Everything fit and it still is not enough players: advancing the anchor
      # only ever looks at a smaller pool, so no later anchor can do better.
      # Without this the no-match case is quadratic in the bucket size.
      size < min and leftover == [] ->
        :none

      true ->
        find_match(rest, blocked, [anchor_group | skipped])
    end
  end

  # Greedily packs whole groups that fit the remaining capacity and are mutually
  # unblocked, preserving FIFO order. A group that does not fit is skipped and
  # stays queued for a later sweep.
  defp pack(groups, blocked, max) do
    {taken, skipped} =
      Enum.reduce(groups, {[], []}, fn group, {taken, skipped} ->
        if count(taken) + count([group]) <= max and compatible?(group, taken, blocked) and
             Gamend.Matchmaking.seatable?(List.flatten([group | taken])) do
          {[group | taken], skipped}
        else
          {taken, [group | skipped]}
        end
      end)

    {Enum.reverse(taken), Enum.reverse(skipped)}
  end

  defp count(groups) do
    Enum.reduce(groups, 0, fn group, acc ->
      acc + Enum.reduce(group, 0, &(Gamend.Matchmaking.size(&1) + &2))
    end)
  end

  defp compatible?(_group, [], _blocked), do: true

  defp compatible?(group, taken, blocked) do
    seated = Enum.flat_map(taken, fn taken_group -> Enum.map(taken_group, & &1.user_id) end)

    not Enum.any?(group, fn ticket ->
      Enum.any?(seated, fn other ->
        MapSet.member?(blocked, Friends.pair_key(ticket.user_id, other))
      end)
    end)
  end
end
