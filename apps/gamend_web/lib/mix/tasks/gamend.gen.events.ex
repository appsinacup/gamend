defmodule Mix.Tasks.Gamend.Gen.Events do
  @moduledoc """
  Writes `clients/events.json`, the realtime table every SDK reads, from the
  one registry of server→client events (`GamendWeb.RealtimeEvents`): a row
  per channel and event, the SDK's signal name for it, and the protobuf
  message it is sent as (`GamendWeb.EventCodec.message_name/2`; null for
  JSON). And `clients/commands.json`, the other direction, from
  `GamendWeb.RealtimeCommands`: a row per event a channel answers, the SDK's
  function name for it, and its payload keys.

  The registry is held to the channel code by `realtime_events_drift_test.exs`
  and its `pb` flag to the codec by `event_codec_coverage_test.exs`, so a
  table generated from it cannot name an event the server never sends or miss
  one it does. It was hand-written before, and had drifted both ways: events
  the server sent were missing (the matchmaking accept's `ready_check_*` on the
  user channel), and events it never sent were listed.

  Generated from it (`clients/sdkgen`): the C++, C#, Rust and Balaur SDKs,
  so the Unreal and Unity packages built on them, and the TypeScript
  declarations' event names. The Godot
  and JavaScript clients' hand-written routing and decoders are held to it by
  `sdk_events_drift_test.exs`.

      mix gamend.gen.events           # write it
      mix gamend.gen.events --check   # fail when it is stale (CI)

  Run from the repository root (or `apps/gamend_web`).
  """

  use Mix.Task

  @shortdoc "Write clients/events.json and commands.json from the realtime registries"

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean])
    Mix.Task.run("compile")

    sync("events.json", render(), opts)
    sync("commands.json", render_commands(), opts)
  end

  defp sync(file, json, opts) do
    path = path(file)

    if opts[:check] do
      if File.read(path) != {:ok, json},
        do: Mix.raise("#{path} is stale: run `mix gamend.gen.events`")
    else
      File.write!(path, json)
      Mix.shell().info("Wrote #{path}")
    end
  end

  @doc "The table, as written."
  def render do
    GamendWeb.RealtimeEvents.all()
    |> Enum.map(fn entry ->
      Jason.OrderedObject.new(
        channel: entry.topic |> String.split(":") |> hd(),
        event: entry.event,
        signal: entry.signal,
        message: GamendWeb.EventCodec.message_name(entry.topic, entry.event)
      )
    end)
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  @doc "The client→server table, as written."
  def render_commands do
    GamendWeb.RealtimeCommands.all()
    |> Enum.map(fn entry ->
      Jason.OrderedObject.new(
        channel: entry.topic |> String.split(":") |> hd(),
        event: entry.event,
        name: entry.name,
        required: entry.required,
        optional: entry.optional
      )
    end)
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp path(file) do
    root =
      Enum.find([".", "../.."], &File.dir?(Path.join(&1, "clients"))) ||
        Mix.raise("no clients/ directory: run from the gamend repository root")

    Path.join([root, "clients", file])
  end
end
