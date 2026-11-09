defmodule GamendWeb.Gettext.CsvColumn do
  @moduledoc """
  The columns of the translations CSV the gettext tasks exchange.
  """

  use Gamend.Names, ~w(source translation msgid domain fuzzy)
end
