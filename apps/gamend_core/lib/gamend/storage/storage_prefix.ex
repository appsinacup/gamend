defmodule Gamend.Storage.StoragePrefix do
  @moduledoc """
  The first segment of an object's key.
  """

  @all ~w(avatars uploads)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
