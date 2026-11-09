defmodule Gamend.Hooks.PluginFile do
  @moduledoc """
  The files and folders of a built plugin.
  """

  use Gamend.Names, ~w(ebin)

  defmacro mix_exs, do: "mix.exs"
end
