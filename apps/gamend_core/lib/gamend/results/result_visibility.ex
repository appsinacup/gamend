defmodule Gamend.Results.ResultVisibility do
  @moduledoc """
  Who can read a play's result.
  """

  @all ~w(server_only public owner_only lobby_members_only owner_or_lobby_member)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
