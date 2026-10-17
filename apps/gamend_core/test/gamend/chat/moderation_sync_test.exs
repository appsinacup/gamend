defmodule Gamend.Chat.ModerationSyncTest do
  # The chat moderation tables kept in step with the other instances
  # (`Gamend.Chat.Moderation.Sync`): a mute put or lifted on another node is
  # applied here, one from this node is not (the writer applied it), the
  # persisted state loads once, and the sweep runs and reschedules.
  use Gamend.DataCase, async: false

  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Chat.Moderation.Sync

  @state %{loaded?: true}

  setup do
    user_id = Ecto.UUID.generate()
    on_exit(fn -> Cache.apply_remote(:mute_deleted, {user_id, "global", nil}) end)
    %{user_id: user_id}
  end

  defp later, do: DateTime.utc_now() |> DateTime.add(3600, :second)

  test "a mute from another node is applied, and its lifting too", %{user_id: user_id} do
    key = {user_id, "global", nil}

    {:noreply, _} =
      Sync.handle_info({:chat_moderation, :mute_put, {key, later()}, :other@node}, @state)

    assert Cache.muted?(user_id, "lobby", Ecto.UUID.generate())

    {:noreply, _} = Sync.handle_info({:chat_moderation, :mute_deleted, key, :other@node}, @state)
    refute Cache.muted?(user_id, "lobby", Ecto.UUID.generate())
  end

  test "an event this node sent is not applied twice", %{user_id: user_id} do
    key = {user_id, "global", nil}

    {:noreply, _} =
      Sync.handle_info({:chat_moderation, :mute_put, {key, later()}, Node.self()}, @state)

    refute Cache.muted?(user_id, "lobby", nil)
  end

  test "a scoped mute covers its own room only", %{user_id: user_id} do
    room = Ecto.UUID.generate()
    key = {user_id, "group", room}

    {:noreply, _} =
      Sync.handle_info({:chat_moderation, :mute_put, {key, later()}, :other@node}, @state)

    assert Cache.muted?(user_id, "group", room)
    refute Cache.muted?(user_id, "group", Ecto.UUID.generate())
    Cache.apply_remote(:mute_deleted, key)
  end

  test "the persisted state loads once; a retry after is a no-op; the sweep reschedules" do
    assert {:noreply, %{loaded?: true}} = Sync.handle_continue(:load_persisted, %{loaded?: false})
    assert {:noreply, %{loaded?: true}} = Sync.handle_info(:retry_load, @state)
    assert {:noreply, @state} = Sync.handle_info(:sweep, @state)
    assert {:noreply, @state} = Sync.handle_info(:anything, @state)
  end

  test "an event of a kind it does not know changes nothing" do
    assert {:noreply, @state} =
             Sync.handle_info({:chat_moderation, :unknown, nil, :other@node}, @state)
  end
end
