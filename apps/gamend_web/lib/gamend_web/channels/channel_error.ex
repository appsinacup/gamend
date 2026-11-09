defmodule GamendWeb.ChannelError do
  @moduledoc """
  The error codes a channel answers with.
  """

  use Gamend.Names,
      ~w(room_not_found not_allowed user_not_found rate_limited ice_rate_limited unauthorized
         forbidden invalid_topic_or_unauthenticated listing_disabled reserved_hook_name
         account_banned)
end
