defmodule Gamend.Sent.SentStatus do
  @moduledoc """
  How a send ended (`Gamend.Sent`): `sent`, `failed` (the relay or the push
  provider refused it, or it ran out of retries), or `invalid` (the device's
  token is dead and was turned off).
  """

  use Gamend.Names, ~w(sent failed invalid)
end
