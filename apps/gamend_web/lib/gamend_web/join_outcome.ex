defmodule GamendWeb.JoinOutcome do
  @moduledoc """
  What a join request became: `POST /groups/:id/join`.
  """

  @all ~w(invited request_approved)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
