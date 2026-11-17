defmodule GamendWeb.TimeFormat do
  @moduledoc """
  How `<.timestamp>` writes an instant: `relative` ("7m ago"), or one of the
  absolute ones `GamendWeb.TimeText.utc/2` and `local_time.js` both read.
  """

  use Gamend.Names, ~w(relative datetime date time full)
end
