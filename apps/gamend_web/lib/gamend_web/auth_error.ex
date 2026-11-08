defmodule GamendWeb.AuthError do
  @moduledoc """
  The codes of a failed sign-in, in the session status the client polls.
  """

  @all ~w(user_not_found authentication_failed provider_already_linked account_not_activated)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
