defmodule GamendWeb.Auth.AuthError do
  @moduledoc """
  The codes of a failed sign-in, in the session status the client polls.
  """

  use Gamend.Names,
      ~w(user_not_found authentication_failed provider_already_linked account_not_activated)
end
