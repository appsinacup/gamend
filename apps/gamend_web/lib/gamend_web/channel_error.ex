defmodule GamendWeb.ChannelError do
  @moduledoc """
  The error codes a channel answers with.
  """

  @all ~w(room_not_found not_allowed user_not_found rate_limited ice_rate_limited unauthorized
         forbidden invalid_topic_or_unauthenticated listing_disabled reserved_hook_name
         account_banned)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
