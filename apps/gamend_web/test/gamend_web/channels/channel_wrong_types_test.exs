defmodule GamendWeb.ChannelWrongTypesTest do
  @moduledoc """
  Every channel command, sent the wrong types, is answered and leaves its
  channel up (`GamendWeb.Testing.WrongTypes.channel_tests/1`).
  """
  use GamendWeb.ChannelCase, async: false
  require GamendWeb.Testing.WrongTypes, as: WrongTypes

  WrongTypes.channel_tests()
end
