defmodule GamendWeb.WebrtcEvent do
  @moduledoc """
  The names of the WebRTC signalling events the user channel pushes, which
  `GamendWeb.EventCodec` encodes too. Written with their `webrtc:` prefix,
  so not a `Gamend.Names` set (a macro cannot be named with a colon).
  """

  @doc "The server's SDP answer."
  defmacro answer, do: "webrtc:answer"

  @doc "A server ICE candidate."
  defmacro ice, do: "webrtc:ice"

  @doc "A DataChannel opened."
  defmacro channel_open, do: "webrtc:channel_open"

  @doc "The DataChannel closed."
  defmacro channel_closed, do: "webrtc:channel_closed"

  @doc "The connection's state changed."
  defmacro state, do: "webrtc:state"
end
