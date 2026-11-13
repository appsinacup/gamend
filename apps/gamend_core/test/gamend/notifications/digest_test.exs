defmodule Gamend.Notifications.DigestTest do
  @moduledoc """
  Notices waiting for a digest email: one per subject, a cap per user, what is
  due asked of the index, and a digest that never goes out given up.
  """

  use Gamend.DataCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.AccountsFixtures
  alias Gamend.Notifications.Digest
  alias Gamend.Notifications.DigestItem
  alias Gamend.SettingsHelpers

  # "reports" sends a weekly digest; "social" has none, so its notices are due
  # at once.
  @weekly "reports"
  @worker "GamendWeb.Workers.NotificationDigest"

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  test "a subject already waiting takes the new words and keeps its place", %{user: user} do
    {:ok, first} = Digest.add(user.id, @weekly, %{"title" => "3 reports", "content" => "three"})
    {:ok, _} = Digest.add(user.id, @weekly, %{"title" => "3 reports", "content" => "four"})
    {:ok, _} = Digest.add(user.id, @weekly, %{"title" => "Another", "content" => "x"})

    assert [%{id: id, text: "four", inserted_at: at}, %{subject: "Another"}] =
             Digest.items(user.id, @weekly)

    assert {id, at} == {first.id, first.inserted_at}
  end

  test "a user holds at most max_digest_items_per_user notices", %{user: user} do
    put_limit(:max_digest_items_per_user, 2)

    {:ok, _} = Digest.add(user.id, @weekly, %{"title" => "one"})
    {:ok, _} = Digest.add(user.id, @weekly, %{"title" => "two"})

    assert {:error, :too_many_items} = Digest.add(user.id, @weekly, %{"title" => "three"})

    assert {:ok, %{text: "again"}} =
             Digest.add(user.id, @weekly, %{"title" => "two", "text" => "again"})

    assert length(Digest.items(user.id, @weekly)) == 2
  end

  test "a pair is due once its oldest notice is as old as its group's period", %{user: user} do
    other = AccountsFixtures.user_fixture()
    now = DateTime.utc_now(:second)

    item(user, @weekly, "old", DateTime.add(now, -8, :day))
    item(user, @weekly, "new", now)
    item(other, @weekly, "recent", DateTime.add(now, -6, :day))
    item(other, "social", "no digest", now)

    assert Enum.sort(Digest.due(now)) == Enum.sort([{user.id, @weekly}, {other.id, "social"}])
  end

  test "a digest queued a day of sweeps and never sent is given up", %{user: user} do
    now = DateTime.utc_now(:second)
    item(user, @weekly, "bounces", DateTime.add(now, -8, :day))

    assert Digest.sweep(now) == 1
    assert [%{args: %{"user_id" => user_id, "group" => @weekly}}] = all_enqueued(worker: @worker)
    assert user_id == user.id
    assert [%{sweeps: 1}] = Digest.items(user.id, @weekly)

    Repo.update_all(DigestItem, set: [sweeps: 24])

    assert Digest.sweep(now) == 0
    assert Digest.items(user.id, @weekly) == []
  end

  defp item(user, group, subject, at) do
    Repo.insert!(%DigestItem{
      user_id: user.id,
      group_key: group,
      subject: subject,
      text: "",
      inserted_at: at
    })
  end

  defp put_limit(key, value) do
    previous = SettingsHelpers.get(:gamend_core, Gamend.Limits, key)
    SettingsHelpers.put(:gamend_core, Gamend.Limits, key, value)

    on_exit(fn ->
      if is_nil(previous),
        do: SettingsHelpers.delete(:gamend_core, Gamend.Limits, key),
        else: SettingsHelpers.put(:gamend_core, Gamend.Limits, key, previous)
    end)
  end
end
