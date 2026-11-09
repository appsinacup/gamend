defmodule Gamend.OAuth.SessionStatus do
  @moduledoc """
  The states of a provider sign-in in progress.
  """

  use Gamend.Names, ~w(pending completed error)
end
