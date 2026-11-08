defmodule GamendWeb.RealtimeEventsDriftTest do
  @moduledoc """
  Keeps `GamendWeb.RealtimeEvents` honest: every event literal pushed by a
  channel must appear in the registry, and every registry event must still
  exist somewhere in the code. Event names are bare strings at their call
  sites, so this grep-style check is the only thing standing between the
  registry (and the admin runtime page built on it) and silent drift.
  """
  use ExUnit.Case, async: true

  @channels_glob Path.expand("../../lib/gamend_web/channels/*.ex", __DIR__)

  # Events forwarded with a variable event name (the literal lives in core, in a
  # constants module, or behind a dispatcher like
  # `SignalingChannel.relay_event_name/1`, rather than at the push site).
  @indirect ~w(
    match_found ticket_queued ticket_cancelled
    outgoing_request incoming_request request_cancelled friend_accepted friend_rejected
    friend_removed friend_blocked friend_unblocked
    user_online user_offline
    tournament_updated tournament_finished tournament_match_ready tournament_match_resolved
    ready_check_started ready_check_updated ready_check_passed ready_check_failed
    user_rejoined offer answer ice
  )

  defp pushed_literals do
    @channels_glob
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      source = File.read!(file)

      # `ChannelEvents.push_member_updated/3` takes the event last; the literal
      # is still written at the channel's call site, so it counts as a push.
      direct =
        Regex.scan(
          ~r/push(?:_event)?\(\s*socket,\s*(?:"([a-z_0-9:]+)"|RealtimeEvent\.([a-z_0-9]+)\(\))/,
          source
        )

      member_updated =
        Regex.scan(
          ~r/push_member_updated\(\s*socket,\s*\w+,\s*(?:"([a-z_0-9:]+)"|RealtimeEvent\.([a-z_0-9]+)\(\))/,
          source
        )

      # A macro of `Gamend.RealtimeEvent` is named after its value.
      Enum.map(direct ++ member_updated, fn [_ | events] ->
        Enum.find(events, &(&1 != ""))
      end)
    end)
    |> MapSet.new()
  end

  test "every pushed event literal is in the registry" do
    registry = MapSet.new(GamendWeb.RealtimeEvents.names())

    missing = MapSet.difference(pushed_literals(), registry)

    assert MapSet.size(missing) == 0,
           "events pushed by channels but missing from RealtimeEvents: " <>
             inspect(MapSet.to_list(missing)) <>
             " — add them to the registry so the docs and admin page stay true"
  end

  test "every registry event still exists in the code" do
    known = MapSet.union(pushed_literals(), MapSet.new(@indirect))

    stale =
      GamendWeb.RealtimeEvents.names()
      |> Enum.reject(&MapSet.member?(known, &1))

    assert stale == [],
           "registry events no longer pushed anywhere: #{inspect(stale)} — " <>
             "remove them from RealtimeEvents (or add to @indirect if forwarded dynamically)"
  end

  # Every event a channel answers by name, as {channel, event}. The clause
  # that takes a variable is the catch-all for an unknown event.
  defp handled_commands do
    for file <- Path.wildcard(@channels_glob),
        String.ends_with?(file, "_channel.ex"),
        channel = Path.basename(file, "_channel.ex"),
        [event] <-
          Regex.scan(~r/def handle_in\(\s*"([a-z_0-9:]+)"/, File.read!(file),
            capture: :all_but_first
          ),
        into: MapSet.new(),
        do: {channel, event}
  end

  defp registered_commands do
    for entry <- GamendWeb.RealtimeCommands.all(),
        into: MapSet.new(),
        do: {entry.topic |> String.split(":") |> hd(), entry.event}
  end

  test "every event a channel answers is in the command registry" do
    missing = MapSet.difference(handled_commands(), registered_commands())

    assert MapSet.size(missing) == 0,
           "channels answer events RealtimeCommands does not list: " <>
             inspect(MapSet.to_list(missing)) <> " — add them, and every SDK a function"
  end

  test "every registered command is still answered by its channel" do
    stale = MapSet.difference(registered_commands(), handled_commands())

    assert MapSet.size(stale) == 0,
           "RealtimeCommands lists what no channel answers: #{inspect(MapSet.to_list(stale))}"
  end
end
