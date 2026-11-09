defmodule GamendWeb.HookErrors.HookErrorCode do
  @moduledoc """
  The error codes of a hook called over RPC.
  """

  use Gamend.Names, ~w(hook_error exception timeout)
end
