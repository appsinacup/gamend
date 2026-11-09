defmodule Gamend.Storage.StoragePrefix do
  @moduledoc """
  The first segment of an object's key.
  """

  use Gamend.Names, ~w(avatars uploads)
end
