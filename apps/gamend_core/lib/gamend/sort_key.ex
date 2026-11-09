defmodule Gamend.SortKey do
  @moduledoc """
  The sort orders of the admin lists of rooms, shared across lobbies, groups, parties and chat.
  """

  use Gamend.Names,
      ~w(updated_at updated_at_asc inserted_at inserted_at_asc title title_desc max_members
         max_members_asc max_users max_users_asc max_size max_size_asc last_seen_at)
end
