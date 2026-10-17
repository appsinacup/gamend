defmodule GamendWeb.LiveSerializerTest do
  @moduledoc """
  The LiveView socket's serializer encodes with Elixir's `JSON`
  (`GamendWeb.LiveSerializer`): the frames must decode to what Phoenix's own
  V2 serializer sends, and a struct only `Jason` can encode must still go out.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.LiveSerializer
  alias Phoenix.Socket.{Broadcast, Message, Reply}
  alias Phoenix.Socket.V2.JSONSerializer

  defp text({:socket_push, :text, iodata}), do: Jason.decode!(IO.iodata_to_binary(iodata))

  test "a reply, a push and a broadcast decode as Phoenix's own serializer's do" do
    payload = %{
      "rendered" => %{
        "0" => "<p>é " <> <<0x2028::utf8>> <> " </script></p>",
        "s" => ["<div>", "</div>"]
      },
      "at" => ~U[2026-10-04 10:00:00Z],
      "n" => nil,
      "f" => 1.5
    }

    reply = %Reply{join_ref: "1", ref: "1", topic: "lv:phx-1", status: :ok, payload: payload}

    message = %Message{
      join_ref: "1",
      ref: nil,
      topic: "lv:phx-1",
      event: "diff",
      payload: payload
    }

    broadcast = %Broadcast{topic: "t", event: "e", payload: payload}

    assert text(LiveSerializer.encode!(reply)) == text(JSONSerializer.encode!(reply))
    assert text(LiveSerializer.encode!(message)) == text(JSONSerializer.encode!(message))
    assert text(LiveSerializer.fastlane!(broadcast)) == text(JSONSerializer.fastlane!(broadcast))
  end

  test "a struct only Jason encodes falls back to Jason instead of failing" do
    # A schema with `@derive Jason.Encoder` and no `JSON.Encoder`.
    word = %Gamend.Chat.FilterWord{}
    assert JSON.Encoder.impl_for(word) == nil

    message = %Message{topic: "lv:phx-1", event: "e", payload: %{"x" => word}}

    assert text(LiveSerializer.encode!(message)) == text(JSONSerializer.encode!(message))
  end

  test "binary frames and decoding are the V2 serializer's" do
    reply = %Reply{join_ref: "1", ref: "2", topic: "t", status: :ok, payload: {:binary, <<1, 2>>}}
    assert LiveSerializer.encode!(reply) == JSONSerializer.encode!(reply)

    raw = ~s(["1","2","lv:phx-1","event",{"value":1}])

    assert LiveSerializer.decode!(raw, opcode: :text) ==
             JSONSerializer.decode!(raw, opcode: :text)
  end
end
