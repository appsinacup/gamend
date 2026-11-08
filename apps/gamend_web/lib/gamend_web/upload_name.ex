defmodule GamendWeb.UploadName do
  @moduledoc """
  The stem of an uploaded file's key.
  """

  @all ~w(icon)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
