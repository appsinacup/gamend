defmodule GamendWeb.Plugs.RateLimitBucket do
  @moduledoc """
  The rate limit buckets the admin page shows by name.
  """

  use Gamend.Names, ~w(auth general client_logs)
end
