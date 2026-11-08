defmodule Gamend.Notifications.PreferenceSwitch do
  @moduledoc """
  The switches that turn a channel off for every group.
  """

  @all ~w(off_all off_email off_push)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
