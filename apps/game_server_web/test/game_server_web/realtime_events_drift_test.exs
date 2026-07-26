defmodule GameServerWeb.RealtimeEventsDriftTest do
  @moduledoc """
  Keeps `GameServerWeb.RealtimeEvents` honest: every event literal pushed by a
  channel must appear in the registry, and every registry event must still
  exist somewhere in the code. Event names are bare strings at their call
  sites, so this grep-style check is the only thing standing between the
  registry (and the admin runtime page built on it) and silent drift.
  """
  use ExUnit.Case, async: true

  @channels_glob Path.expand("../../lib/game_server_web/channels/*.ex", __DIR__)

  # Events forwarded with a variable event name (the literal lives in core or
  # in a constants module rather than at the push site).
  @indirect ~w(
    match_found
    user_online user_offline
    tournament_updated tournament_finished tournament_match_ready tournament_match_resolved
    ready_check_started ready_check_updated ready_check_passed ready_check_failed
  )

  defp pushed_literals do
    @channels_glob
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      source = File.read!(file)

      Regex.scan(~r/push(?:_event)?\(\s*socket,\s*"([a-z_0-9:]+)"/, source)
      |> Enum.map(fn [_, event] -> event end)
    end)
    |> MapSet.new()
  end

  test "every pushed event literal is in the registry" do
    registry = MapSet.new(GameServerWeb.RealtimeEvents.names())

    missing = MapSet.difference(pushed_literals(), registry)

    assert MapSet.size(missing) == 0,
           "events pushed by channels but missing from RealtimeEvents: " <>
             inspect(MapSet.to_list(missing)) <>
             " — add them to the registry so the docs and admin page stay true"
  end

  test "every registry event still exists in the code" do
    known = MapSet.union(pushed_literals(), MapSet.new(@indirect))

    stale =
      GameServerWeb.RealtimeEvents.names()
      |> Enum.reject(&MapSet.member?(known, &1))

    assert stale == [],
           "registry events no longer pushed anywhere: #{inspect(stale)} — " <>
             "remove them from RealtimeEvents (or add to @indirect if forwarded dynamically)"
  end
end
