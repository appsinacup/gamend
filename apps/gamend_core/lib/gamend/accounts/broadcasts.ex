defmodule Gamend.Accounts.Broadcasts do
  @moduledoc """
  Telling connected clients a user changed: the `user:<id>` topic, and the
  member and friend topics that show that user to others.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name.

  Each runs after commit when called inside a transaction (`Gamend.AfterCommit`),
  lookups included, so the fan-out sees and announces only committed state.
  """

  import Ecto.Query, warn: false
  alias Gamend.Accounts
  alias Gamend.Accounts.User

  @doc """
  Broadcast that the given user has been updated.

  This helper is intentionally small and only broadcasts a compact payload
  intended for client consumption through the `user:<id>` topic.
  """
  @spec broadcast_user_update(User.t()) :: :ok
  def broadcast_user_update(%User{} = user) do
    Gamend.AfterCommit.defer(fn ->
      payload = serialize_user_payload(user)
      topic = "user:#{user.id}"

      Gamend.Broadcast.publish(
        topic,
        %Phoenix.Socket.Broadcast{topic: topic, event: "updated", payload: payload}
      )

      :ok
    end)
  end

  @doc """
  Broadcast a `member_updated` event to the user's current lobby and
  party channels so other members see the profile change (display name, avatar,
  metadata, etc.) in real-time.

  This is fire-and-forget and safe to call even when the user is not in a lobby
  or party.
  """
  @spec broadcast_member_update(User.t()) :: :ok
  def broadcast_member_update(%User{} = user) do
    Gamend.AfterCommit.defer(fn ->
      if user.lobby_id do
        Gamend.Lobbies.broadcast_member_presence(
          user.lobby_id,
          {:member_updated, user.id}
        )
      end

      if user.party_id do
        Gamend.Parties.broadcast_member_presence(
          user.party_id,
          {:member_updated, user.id}
        )
      end

      # Broadcast to all groups the user belongs to
      for group_id <- Gamend.Groups.user_group_ids(user.id) do
        Gamend.Groups.broadcast_member_presence(
          group_id,
          {:member_updated, user.id}
        )
      end

      broadcast_friend_update(user)
      :ok
    end)
  end

  @doc """
  Broadcast a `friend_updated` event to all accepted friends.

  Used when public user data changes: map presence, display name, avatar,
  player metadata, ship metadata, lobby/party state, etc.
  """
  @spec broadcast_friend_update(User.t()) :: :ok
  def broadcast_friend_update(%User{} = user) do
    Gamend.AfterCommit.defer(fn ->
      payload = User.serialize_brief(user) |> Map.put(:user_id, user.id)

      for friend_id <- Gamend.Friends.friend_ids(user.id) do
        topic = "user:#{friend_id}"

        Gamend.Broadcast.publish(
          topic,
          %Phoenix.Socket.Broadcast{topic: topic, event: "friend_updated", payload: payload}
        )
      end

      :ok
    end)
  end

  @doc """
  Serialize a user into the compact payload used by realtime updates.
  """
  @spec serialize_user_payload(User.t()) :: map()
  def serialize_user_payload(%User{} = user) do
    %{
      id: user.id,
      email: user.email || "",
      profile_url: user.profile_url || "",
      metadata: user.metadata || %{},
      username: user.username || "",
      display_name: user.display_name || "",
      lobby_id: user.lobby_id || "",
      party_id: user.party_id || "",
      is_online: user.is_online || false,
      last_seen_at: User.last_seen_at_or_fallback(user),
      linked_providers: Accounts.get_linked_providers(user),
      has_password: Accounts.has_password?(user)
    }
  end
end
