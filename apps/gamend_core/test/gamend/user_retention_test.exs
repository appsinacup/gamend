defmodule Gamend.UserRetentionTest do
  @moduledoc """
  Account retention: both windows, and the accounts the sweep must never touch.
  """
  use Gamend.DataCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.{InactivityNotifier, User}
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias Gamend.Retention

  setup do
    old = Application.get_env(:gamend_core, Retention, [])
    on_exit(fn -> Application.put_env(:gamend_core, Retention, old) end)
    :ok
  end

  defp configure(opts) do
    existing = Application.get_env(:gamend_core, Retention, [])
    Application.put_env(:gamend_core, Retention, Keyword.merge(existing, opts))
  end

  defp anonymous_user(last_seen_days_ago) do
    {:ok, user} =
      Accounts.find_or_create_from_device("device-#{System.unique_integer([:positive])}")

    backdate(user, last_seen_days_ago)
  end

  defp registered_user(last_seen_days_ago) do
    AccountsFixtures.user_fixture() |> backdate(last_seen_days_ago)
  end

  # `is_admin` forced off: the first account in a fresh database is auto-promoted
  # and would be silently exempt from the sweep.
  defp backdate(user, days) do
    at = DateTime.add(DateTime.utc_now(:second), -days, :day)

    user
    |> Ecto.Changeset.change(last_seen_at: at, is_admin: false)
    |> Repo.update!()
  end

  defp exists?(user), do: Repo.exists?(from(u in User, where: u.id == ^user.id))

  defp stamp_warned(user, days_ago) do
    at = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.to_iso8601()

    user
    |> Ecto.Changeset.change(metadata: Map.put(user.metadata, "retention_warned_at", at))
    |> Repo.update!()
  end

  describe "anonymous accounts" do
    test "an anonymous account past the window is deleted" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(120)

      Retention.prune_all()

      refute exists?(user)
    end

    test "an anonymous account inside the window is kept" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(30)

      Retention.prune_all()

      assert exists?(user)
    end

    test "0 disables the sweep entirely" do
      configure(anonymous_users_days: 0)
      user = anonymous_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end

    test "an account that has never connected is dated from when it was created" do
      configure(anonymous_users_days: 90)

      {:ok, user} = Accounts.find_or_create_from_device("never-seen-#{System.unique_integer()}")

      user =
        user
        |> Ecto.Changeset.change(
          last_seen_at: nil,
          is_admin: false,
          inserted_at: DateTime.add(DateTime.utc_now(:second), -120, :day)
        )
        |> Repo.update!()

      Retention.prune_all()

      refute exists?(user)
    end

    test "a registered account is not touched by the anonymous sweep" do
      configure(anonymous_users_days: 90, inactive_users_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end
  end

  describe "unconfirmed accounts" do
    # `confirmed_at` forced off too: the first account is confirmed on sign-up.
    defp unconfirmed_user(last_seen_days_ago) do
      AccountsFixtures.unconfirmed_user_fixture()
      |> Ecto.Changeset.change(confirmed_at: nil)
      |> Repo.update!()
      |> backdate(last_seen_days_ago)
    end

    test "an unconfirmed account inactive past the window is deleted" do
      configure(unconfirmed_users_days: 30)
      user = unconfirmed_user(45)

      Retention.prune_all()

      refute exists?(user)
    end

    test "an unconfirmed account still playing is kept" do
      configure(unconfirmed_users_days: 30)
      user = unconfirmed_user(5)

      Retention.prune_all()

      assert exists?(user)
    end

    test "a confirmed account is not touched by the unconfirmed sweep" do
      configure(unconfirmed_users_days: 30, inactive_users_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end

    test "an unconfirmed account with a provider login is kept" do
      configure(unconfirmed_users_days: 30)

      user =
        unconfirmed_user(9999)
        |> Ecto.Changeset.change(discord_id: "d-#{System.unique_integer([:positive])}")
        |> Repo.update!()

      Retention.prune_all()

      assert exists?(user)
    end

    test "0 disables the sweep" do
      configure(unconfirmed_users_days: 0)
      user = unconfirmed_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end
  end

  describe "exclusions" do
    test "an admin is never deleted" do
      configure(anonymous_users_days: 90)

      user =
        anonymous_user(9999)
        |> Ecto.Changeset.change(is_admin: true)
        |> Repo.update!()

      Retention.prune_all()

      assert exists?(user)
    end

    test "an account holding a purchase is never deleted" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(9999)

      Repo.insert!(%Gamend.Payments.Purchase{
        user_id: user.id,
        provider: "stripe",
        order_id: "order-#{System.unique_integer([:positive])}",
        status: "completed"
      })

      Retention.prune_all()

      assert exists?(user)
    end

    test "an account holding an entitlement is never deleted" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(9999)

      Repo.insert!(%Gamend.Payments.Entitlement{
        user_id: user.id,
        key: "monthly_pass",
        status: "active"
      })

      Retention.prune_all()

      assert exists?(user)
    end
  end

  describe "storage" do
    # Storage has no foreign key to cascade, so avatars used to outlive the
    # account indefinitely.
    test "deleting an account removes its stored objects" do
      dir =
        Path.join(System.tmp_dir!(), "gs_retention_storage_#{System.unique_integer([:positive])}")

      old = Application.get_env(:gamend_core, Gamend.Storage.Local)
      Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

      on_exit(fn ->
        File.rm_rf(dir)
        if old, do: Application.put_env(:gamend_core, Gamend.Storage.Local, old)
      end)

      configure(anonymous_users_days: 90)
      user = anonymous_user(120)
      other = anonymous_user(1)

      {:ok, _} = Gamend.Storage.put("avatars/#{user.id}/a.png", "x")
      {:ok, _} = Gamend.Storage.put("avatars/#{user.id}/b.png", "y")
      {:ok, _} = Gamend.Storage.put("avatars/#{other.id}/a.png", "z")

      Retention.prune_all()

      refute exists?(user)
      refute Gamend.Storage.exists?("avatars/#{user.id}/a.png")
      refute Gamend.Storage.exists?("avatars/#{user.id}/b.png")
      assert Gamend.Storage.exists?("avatars/#{other.id}/a.png")
    end
  end

  describe "inactive registered accounts" do
    test "0 turns it off" do
      configure(inactive_users_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end

    test "is warned first, and not deleted on the same pass" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 30)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)

      # Filter args in Elixir: JSON-path SQL differs per adapter (json_extract
      # vs ->>), while Oban.Job decodes args to a map on both.
      warned_user_ids =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Gamend.Accounts.InactivityNotifier",
            select: j.args
          )
        )
        |> Enum.map(& &1["user_id"])

      assert user.id in warned_user_ids
    end

    test "is deleted once the warning has been delivered" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 30)
      user = registered_user(9999)

      assert :ok =
               perform_job(InactivityNotifier, %{"user_id" => user.id, "delete_after_days" => 730})

      Retention.prune_all()

      refute exists?(user)
    end

    # Warned, came back, went quiet again: that old warning was notice of a
    # deletion the sign-in cancelled, so it must not license the next one.
    test "a warning older than the last sign-in does not count" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 30)

      user =
        registered_user(800)
        |> stamp_warned(900)

      Retention.prune_all()

      assert exists?(user)
    end

    test "with warnings disabled the account is deleted directly" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      refute exists?(user)
    end
  end
end
