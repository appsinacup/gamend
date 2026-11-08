defmodule GamendWeb.ChannelPush do
  @moduledoc """
  Format-aware channel push.

  Sockets connected with `?format=protobuf` receive events with a protobuf
  mapping (see `GamendWeb.EventCodec`) as binary frames; everything else
  — including all traffic on default JSON sockets — is pushed as JSON.
  """

  alias GamendWeb.EventCodec

  require GamendWeb.WsFormat, as: WsFormat

  def push_event(socket, event, payload) do
    with WsFormat.protobuf() <- socket.assigns[:ws_format],
         {:ok, bin} <- EventCodec.encode(socket.topic, event, payload) do
      Phoenix.Channel.push(socket, event, {:binary, IO.iodata_to_binary(bin)})
    else
      _ -> Phoenix.Channel.push(socket, event, payload)
    end
  end
end
