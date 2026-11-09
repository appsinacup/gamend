defmodule GamendWeb.WsFormat do
  @moduledoc """
  How a socket's frames are encoded.
  """

  use Gamend.Names, ~w(json protobuf)
end
