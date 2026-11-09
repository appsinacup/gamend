defmodule Gamend.GDScript.Word do
  @moduledoc """
  The words the compiler's stages share: two keywords, and the name of a source
  that has no file.
  """

  defmacro break, do: "break"

  defmacro continue, do: "continue"

  defmacro nofile, do: "nofile"
end
