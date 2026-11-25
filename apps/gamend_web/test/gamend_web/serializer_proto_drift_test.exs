defmodule GamendWeb.SerializerProtoDriftTest do
  @moduledoc """
  Keeps the protobuf wire contract honest against the JSON one: every key a
  `GamendWeb.Serializers` payload carries must be representable in the
  corresponding proto message (per the documented transforms — `*_at` becomes
  `*_at_ms`, `metadata` becomes `metadata_json`/`metadata_pb`).

  Grep-style like RealtimeEventsDriftTest, because the drift it hunts is
  structural: a field such as `Lobby.state` missing from the proto means every
  protobuf client silently reads no lobby state at all, and nothing crashes;
  the field just never arrives. Payloads assembled outside Serializers (user presence payloads,
  member events) are covered by the channel tests instead.
  """
  use ExUnit.Case, async: true

  # Scanned one file at a time: a file's last function otherwise ran on into
  # the next file's module body and collected its schema fields as keys.
  @serializer_srcs Enum.map(
                     [
                       "../../lib/gamend_web/serializers.ex",
                       "../../../gamend_core/lib/gamend/accounts/broadcasts.ex",
                       "../../../gamend_core/lib/gamend/accounts/user.ex"
                     ],
                     &File.read!(Path.expand(&1, __DIR__))
                   )
  @proto_src File.read!(Path.expand("../../../../proto/gamend_realtime.proto", __DIR__))

  @pairs [
    {"serialize_lobby", "Lobby"},
    {"serialize_group", "Group"},
    {"serialize_party", "Party"},
    {"serialize_notification", "Notification"},
    {"serialize_chat_message", "ChatMessage"},
    {"serialize_quest_progress", "QuestProgress"},
    {"serialize_ready_check", "ReadyCheckState"},
    {"serialize_ready_participant", "ReadyCheckParticipant"},
    {"serialize_user_payload", "User"},
    {"serialize_brief", "UserBrief"}
  ]

  test "every Serializers payload key is representable in its proto message" do
    keys =
      Enum.reduce(@serializer_srcs, %{}, fn src, acc ->
        Map.merge(acc, keys_by_function(src), fn _name, a, b -> MapSet.union(a, b) end)
      end)

    fields = fields_by_message()

    problems =
      for {func, message} <- @pairs,
          key <- Map.fetch!(keys, func),
          not representable?(key, Map.fetch!(fields, message)) do
        "#{func} sends \"#{key}\" but proto message #{message} cannot carry it"
      end

    assert problems == [],
           Enum.join(problems, "\n") <>
             "\n— add the field to proto/gamend_realtime.proto (and regenerate " <>
             "both the Elixir module and the Godot bindings via mix host.proto.gen), " <>
             "or it silently never reaches protobuf clients"
  end

  # A JSON key is representable when the proto has it verbatim or through the
  # documented transforms.
  defp representable?(key, fields) do
    key in fields or
      "#{key}_ms" in fields or
      (key == "metadata" and "metadata_json" in fields)
  end

  # Map keys per serializer function, across all its clauses: `key: value`
  # literals plus bare `:key` atoms threaded through maybe_put/Map.put. A
  # body ends at the next def OR the next @doc/@spec, so a following
  # function's typespec never leaks its keys into the previous body.
  defp keys_by_function(src) do
    bounds =
      Regex.scan(~r/^  (?:defp? (\w+)|@spec|@doc)/m, src, return: :index)
      |> Enum.map(fn
        [{start, _}, {ns, nl}] when nl > 0 ->
          {binary_part(src, ns, nl), start}

        [{start, _} | _] ->
          {nil, start}
      end)

    # Each bound paired with where the next one begins — the last runs to the
    # end of the file. Streamed rather than `starts ++ [eof]` then `tl/1`: the
    # append walked the whole list to add one element, and the offset the
    # dropped head carried was never used.
    nexts =
      bounds
      |> Enum.drop(1)
      |> Enum.map(&elem(&1, 1))
      |> Stream.concat([byte_size(src)])

    bounds
    |> Enum.zip(nexts)
    |> Enum.reduce(%{}, fn
      {{nil, _start}, _next}, acc ->
        acc

      {{name, start}, next}, acc ->
        body = binary_part(src, start, next - start)

        keys =
          (Regex.scan(~r/^\s+(\w+): /m, body) ++ Regex.scan(~r/:(\w+),$/m, body))
          |> Enum.map(fn [_, k] -> k end)

        Map.update(acc, name, MapSet.new(keys), &MapSet.union(&1, MapSet.new(keys)))
    end)
  end

  defp fields_by_message do
    Regex.scan(~r/message (\w+) \{(.*?)\n\}/s, @proto_src)
    |> Map.new(fn [_, name, body] ->
      fields =
        Regex.scan(~r/ (\w+) = \d+;/, body)
        |> Enum.map(fn [_, f] -> f end)
        |> MapSet.new()

      {name, fields}
    end)
  end
end
