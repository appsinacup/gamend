defmodule GamendWeb.HookErrorCode do
  @moduledoc """
  The error codes of a hook called over RPC.
  """

  @all ~w(hook_error exception timeout)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
