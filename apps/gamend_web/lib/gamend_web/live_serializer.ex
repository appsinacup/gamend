defmodule GamendWeb.LiveSerializer do
  @moduledoc """
  The LiveView socket's message serializer: Phoenix's V2 JSON serializer, with
  text frames encoded by Elixir's `JSON` instead of `Phoenix.json_library()`.

  A LiveView join reply is the whole rendered page as JSON (76-172 KB on this
  site's pages), and encoding it was the largest single cost of a join after
  rendering. On real join replies `JSON` encoded in 55-95% of Jason's time
  (2026-10-04, `JSON` 0.6-1.2 ms against Jason 0.8-1.8 ms), with output that
  decodes to the same term.

  Only this socket: `Phoenix.json_library/0` stays Jason everywhere else,
  because structs across the app implement `Jason.Encoder` and not
  `JSON.Encoder`. A payload holding one here (a `push_event/3` or a reply
  carrying such a struct) falls back to the library rather than failing.
  Binary frames and decoding are the V2 serializer's own.
  """
  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.Broadcast
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Reply
  alias Phoenix.Socket.V2.JSONSerializer

  @impl true
  def fastlane!(%Broadcast{payload: %{}} = msg),
    do: {:socket_push, :text, encode([nil, nil, msg.topic, msg.event, msg.payload])}

  def fastlane!(msg), do: JSONSerializer.fastlane!(msg)

  @impl true
  def encode!(%Reply{payload: {:binary, _}} = reply), do: JSONSerializer.encode!(reply)

  def encode!(%Reply{} = reply) do
    data = [
      reply.join_ref,
      reply.ref,
      reply.topic,
      "phx_reply",
      %{status: reply.status, response: reply.payload}
    ]

    {:socket_push, :text, encode(data)}
  end

  def encode!(%Message{payload: %{}} = msg),
    do: {:socket_push, :text, encode([msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload])}

  def encode!(msg), do: JSONSerializer.encode!(msg)

  @impl true
  def decode!(raw_message, opts), do: JSONSerializer.decode!(raw_message, opts)

  @doc false
  def encode(data) do
    JSON.encode_to_iodata!(data)
  rescue
    Protocol.UndefinedError -> Phoenix.json_library().encode_to_iodata!(data)
  end
end
