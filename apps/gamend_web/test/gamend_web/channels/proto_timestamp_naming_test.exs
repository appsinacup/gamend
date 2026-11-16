defmodule GamendWeb.ProtoTimestampNamingTest do
  @moduledoc """
  Realtime timestamps are named after the REST field they mirror.

  JSON sends `deadline_at` as an ISO 8601 string; protobuf, which has no
  timestamp type, sends the same instant as `deadline_at_ms`. Strip `_ms` and
  you have the REST name — which is what lets a client map one onto the other
  without a lookup table.

  `deadline_ms` broke that rule for two messages, and nothing caught it: a
  client reading the name it expected got a silent zero, and the party panel's
  countdown was blank for as long as it existed. Hence a test — the cost of the
  convention slipping is invisible, so it has to be visible here.
  """
  use ExUnit.Case, async: true

  @proto Path.expand("../../../../../proto/gamend_realtime.proto", __DIR__)

  # An int64 that holds an instant. `quantity` and `balance` are the only other
  # int64s in the file, and neither mentions time.
  @timestampish ~r/(_at|deadline|expires|_time)/

  test "every realtime timestamp is named <field>_at_ms, or says what unit it is" do
    offenders =
      @proto
      |> File.read!()
      |> then(
        &Regex.scan(~r/^\s+(?:optional )?int64 ([a-z_0-9]+) =/m, &1, capture: :all_but_first)
      )
      |> Enum.map(&hd/1)
      |> Enum.uniq()
      |> Enum.filter(&Regex.match?(@timestampish, &1))
      |> Enum.reject(&(String.ends_with?(&1, "_at_ms") or String.ends_with?(&1, "_seconds")))

    assert offenders == [],
           "these carry an instant but not the shape a client can map back to the " <>
             "REST name — rename to <field>_at_ms (or <field>_seconds if it really " <>
             "is not milliseconds):\n  " <> Enum.join(offenders, "\n  ")
  end
end
