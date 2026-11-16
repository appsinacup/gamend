defmodule Gamend.Chat.ModerationSyncTest do
  # Chat moderation kept in step with the other instances: a mute (a chat ban,
  # carried by `Gamend.Bans.Sync`) put or lifted on another node is applied
  # here (one from this node is skipped: bans/sync_test.exs), and the
  # blocklist (`Gamend.Chat.Moderation.Sync`) loads once.
  use Gamend.DataCase, async: false

  alias Gamend.Bans
  alias Gamend.Chat.Moderation.Sync

  @state %{loaded?: true}

  setup do
    Bans.Cache.init_table()
    :ets.delete_all_objects(:bans)
    %{user_id: Ecto.UUID.generate()}
  end

  defp later, do: DateTime.utc_now() |> DateTime.add(3600, :second)

  test "a mute from another node is applied, and its lifting too", %{user_id: user_id} do
    key = {:chat, user_id, "global"}

    {:noreply, _} = Bans.Sync.handle_info({:bans, :put, {key, later()}, :other@node}, @state)
    assert Bans.muted?(user_id, "lobby", Ecto.UUID.generate())

    {:noreply, _} = Bans.Sync.handle_info({:bans, :deleted, key, :other@node}, @state)
    refute Bans.muted?(user_id, "lobby", Ecto.UUID.generate())
  end

  test "a scoped mute covers its own room only", %{user_id: user_id} do
    room = Ecto.UUID.generate()
    key = {:chat, user_id, {"group", room}}

    {:noreply, _} = Bans.Sync.handle_info({:bans, :put, {key, later()}, :other@node}, @state)

    assert Bans.muted?(user_id, "group", room)
    refute Bans.muted?(user_id, "group", Ecto.UUID.generate())
  end

  test "the blocklist loads once; a retry after is a no-op" do
    assert {:noreply, %{loaded?: true}} = Sync.handle_continue(:load_persisted, %{loaded?: false})
    assert {:noreply, %{loaded?: true}} = Sync.handle_info(:retry_load, @state)
    assert {:noreply, @state} = Sync.handle_info(:anything, @state)
  end

  test "an event of a kind it does not know changes nothing" do
    assert {:noreply, @state} =
             Sync.handle_info({:chat_moderation, :unknown, nil, :other@node}, @state)
  end
end
