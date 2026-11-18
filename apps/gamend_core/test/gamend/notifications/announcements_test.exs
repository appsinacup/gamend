defmodule Gamend.Notifications.AnnouncementsTest do
  use Gamend.DataCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Bans
  alias Gamend.Notifications
  alias Gamend.Notifications.Announcements
  alias Gamend.Notifications.AnnouncementWorker
  alias Gamend.Notifications.Preferences

  # Runs the queued batches oldest first, and the ones they queue, until none
  # is left. A manual-mode job stays queued after `perform_job/2`, so each is
  # deleted once it ran.
  defp run_all do
    case all_enqueued(worker: AnnouncementWorker) do
      [] ->
        :ok

      jobs ->
        for job <- Enum.sort_by(jobs, & &1.id) do
          assert :ok = perform_job(AnnouncementWorker, job.args)
          Gamend.Repo.delete!(job)
        end

        run_all()
    end
  end

  defp titles(user), do: user.id |> Notifications.list_notifications() |> Enum.map(& &1.title)

  describe "announce_to_all/1" do
    test "queues one job and answers how many accounts it goes to" do
      for _ <- 1..3, do: AccountsFixtures.user_fixture()
      audience = Announcements.count_audience()

      assert {:ok, ^audience} =
               Notifications.announce_to_all(%{
                 "title" => "Season 2",
                 "content" => "Out now",
                 "url" => "/news"
               })

      assert audience >= 3
      assert [job] = all_enqueued(worker: AnnouncementWorker)
      assert job.args["title"] == "Season 2"
      assert job.args["after"] == nil
      assert job.args["site_only"] == false
    end

    test "every player gets their own row, in the announcements group" do
      players = for _ <- 1..2, do: AccountsFixtures.user_fixture()

      assert {:ok, _count} =
               Notifications.announce_to_all(%{"title" => "Maintenance", "url" => "/news"})

      run_all()

      for player <- players do
        assert [row] = Notifications.list_notifications(player.id)
        assert row.title == "Maintenance"
        assert row.sender_id == player.id
        assert row.metadata["type"] == "announcement"
        assert row.metadata["group"] == "announcements"
        assert row.metadata["url"] == "/news"
      end
    end

    test "skips a banned account and one not activated" do
      player = AccountsFixtures.user_fixture()
      banned = AccountsFixtures.user_fixture()
      inactive = AccountsFixtures.user_fixture()

      {:ok, _ban} = Bans.ban(:account, banned.id)
      {:ok, _user} = Accounts.update_user(inactive, %{is_activated: false})

      assert {:ok, _count} = Notifications.announce_to_all(%{"title" => "Hello all"})
      run_all()

      assert titles(player) == ["Hello all"]
      assert titles(banned) == []
      assert titles(inactive) == []
    end

    test "email goes only to a player who turned it on" do
      quiet = AccountsFixtures.user_fixture()
      reader = AccountsFixtures.user_fixture()
      {:ok, _user} = Preferences.put(reader, "announcements", "email", true)

      assert {:ok, _count} = Notifications.announce_to_all(%{"title" => "Patch notes"})
      run_all()

      assert [job] = all_enqueued(queue: :mailers)
      assert job.args["user_id"] == reader.id
      assert job.args["group"] == "announcements"
      assert titles(quiet) == ["Patch notes"]
    end

    test "site_only sends no email, even to a player who wants it" do
      reader = AccountsFixtures.user_fixture()
      {:ok, _user} = Preferences.put(reader, "announcements", "email", true)

      assert {:ok, _count} =
               Notifications.announce_to_all(%{"title" => "Quiet news", "site_only" => true})

      run_all()

      assert titles(reader) == ["Quiet news"]
      assert all_enqueued(queue: :mailers) == []
    end

    test "the same title again refreshes the row rather than adding one" do
      player = AccountsFixtures.user_fixture()

      assert {:ok, _} = Notifications.announce_to_all(%{"title" => "News", "content" => "one"})
      run_all()
      assert {:ok, _} = Notifications.announce_to_all(%{"title" => "News", "content" => "two"})
      run_all()

      assert [row] = Notifications.list_notifications(player.id)
      assert row.content == "two"
    end

    test "refuses a blank title and a link off the site" do
      assert {:error, changeset} = Notifications.announce_to_all(%{"title" => "  "})
      assert "can't be blank" in errors_on(changeset).title

      for url <- ["https://example.com/x", "//example.com/x", "news", "/a b"] do
        assert {:error, changeset} =
                 Notifications.announce_to_all(%{"title" => "T", "url" => url})

        assert errors_on(changeset).url != []
      end

      assert all_enqueued(worker: AnnouncementWorker) == []
    end
  end

  describe "send_batch/2" do
    test "a full batch queues the next from its last id, and the last one stops" do
      players =
        for(_ <- 1..3, do: AccountsFixtures.user_fixture())
        |> Enum.sort_by(& &1.id)

      args = %{"id" => Gamend.UUIDv7.generate(), "title" => "Batched", "after" => nil}

      assert :ok = Announcements.send_batch(args, 2)
      assert [next] = all_enqueued(worker: AnnouncementWorker)
      assert next.args["after"] == Enum.at(players, 1).id

      assert :ok = Announcements.send_batch(next.args, 2)
      assert [^next] = all_enqueued(worker: AnnouncementWorker)

      for player <- players, do: assert(titles(player) == ["Batched"])
    end

    test "a batch run twice queues its successor once" do
      for _ <- 1..3, do: AccountsFixtures.user_fixture()
      args = %{"id" => Gamend.UUIDv7.generate(), "title" => "Twice", "after" => nil}

      assert :ok = Announcements.send_batch(args, 1)
      assert :ok = Announcements.send_batch(args, 1)

      assert [_next] = all_enqueued(worker: AnnouncementWorker)
    end
  end
end
