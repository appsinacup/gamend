defmodule GamendWeb.Plugs.RateLimitBucket do
  @moduledoc """
  The rate limit buckets the admin page shows by name.
  """

  @all ~w(auth general client_logs)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
