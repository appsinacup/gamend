defmodule GamendWeb.AdminLive.RuntimeRow do
  @moduledoc """
  What a row of the admin runtime page says: a hook's kind and source, and
  what a foreign key does on delete.
  """

  use Gamend.Names, ~w(pipeline fanout plugin server cascade nilify)
end
