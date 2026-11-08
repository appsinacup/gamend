defmodule Gamend.SortKey do
  @moduledoc """
  The sort orders of the admin lists of rooms, shared across lobbies, groups, parties and chat.
  """

  @all ~w(updated_at updated_at_asc inserted_at inserted_at_asc title title_desc max_members
         max_members_asc max_users max_size)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
