defmodule Gamend.Accounts.AgeGrandfatheringTest do
  @moduledoc """
  The backfill that protects existing players.

  `AddUserAgeFields` stamps `grandfathered_at` on every row that exists when it
  runs, and `AgePolicy` reads that as "unknown, but do not restrict yet". If the
  statement silently does nothing — a timestamp format the adapter cannot read
  back, a column that stayed NULL — the symptom is not an error. It is every
  current player losing chat, purchasing and their leaderboard identity on
  deploy.

  A fresh test database has no pre-existing rows, so the migration's own backfill
  touches nothing here. These tests run the same statement against a row that
  does exist, which is what makes the format portable rather than assumed.
  """
  use Gamend.DataCase, async: true

  alias Gamend.Accounts.AgePolicy
  alias Gamend.Accounts.User
  alias Gamend.Repo

  import Gamend.AccountsFixtures

  defp backfill_sql do
    now = NaiveDateTime.utc_now(:second) |> NaiveDateTime.to_string()
    "UPDATE users SET grandfathered_at = '#{now}' WHERE grandfathered_at IS NULL"
  end

  test "a new account is not grandfathered and is treated as a child" do
    user = user_fixture()

    assert user.grandfathered_at == nil
    assert user.account_class == "unknown"
    refute AgePolicy.grandfathered?(user)
    assert AgePolicy.effective_class(user) == :child
  end

  test "the migration's statement stamps an existing row, and Ecto reads it back" do
    user = user_fixture()
    Repo.query!("UPDATE users SET grandfathered_at = NULL WHERE id = '#{user.id}'")

    {:ok, _} = Repo.query(backfill_sql())

    reloaded = Repo.get!(User, user.id)

    # The read-back is the point: a timestamp written in a format the adapter
    # cannot parse would either raise here or come back nil, and both are the
    # failure this test exists to catch.
    assert %DateTime{} = reloaded.grandfathered_at
    assert AgePolicy.grandfathered?(reloaded)
    assert AgePolicy.effective_class(reloaded) == :adult
  end

  test "the backfill only touches rows that have not been stamped" do
    stamped = user_fixture()
    {:ok, _} = Repo.query(backfill_sql())
    first = Repo.get!(User, stamped.id).grandfathered_at

    # A second run must not move an existing stamp — it is a record of when the
    # account predated the gate, not a heartbeat.
    {:ok, _} = Repo.query(backfill_sql())
    assert Repo.get!(User, stamped.id).grandfathered_at == first
  end

  test "a device-auth account is child-restricted, not grandfathered" do
    # Device auth mints a fully capable account from one unauthenticated request
    # with no email and no proof of anything, so it is the account type an age
    # gate is easiest to walk around. It must land closed by construction:
    # `unknown` with no grandfathering, which `effective_class/2` reads as
    # `:child`. Only the migration stamps `grandfathered_at`, and it ran before
    # this account existed.
    {:ok, user} =
      Gamend.Accounts.find_or_create_from_device("device-#{System.unique_integer([:positive])}")

    assert user.account_class == "unknown"
    assert user.grandfathered_at == nil
    refute AgePolicy.grandfathered?(user)
    assert AgePolicy.effective_class(user) == :child
  end

  describe "set_user_age/2" do
    test "stores the answer, derives the class, and clears the grandfathering" do
      user = user_fixture()
      {:ok, _} = Repo.query(backfill_sql())
      grandfathered = Repo.get!(User, user.id)
      assert AgePolicy.effective_class(grandfathered) == :adult

      {:ok, updated} =
        Gamend.Accounts.set_user_age(grandfathered, %{
          "birth_year" => 2016,
          "birth_month" => 3,
          "age_country" => "ro",
          "age_method" => "self_declared"
        })

      assert updated.birth_year == 2016
      assert updated.birth_month == 3
      # Upcased on the way in, so the lookup never depends on the caller.
      assert updated.age_country == "RO"
      assert updated.account_class == "child"
      assert updated.grandfathered_at == nil
      assert %DateTime{} = updated.age_locked_at
    end

    test "the day is never stored, because it is never accepted" do
      user = user_fixture()

      {:ok, updated} =
        Gamend.Accounts.set_user_age(user, %{
          "birth_year" => 2000,
          "birth_month" => 6,
          "birth_day" => 14,
          "age_method" => "self_declared"
        })

      refute Map.has_key?(updated, :birth_day)
      assert updated.birth_year == 2000
    end

    test "the same age is a child in Romania and a teen in the US" do
      for {country, expected} <- [{"RO", "child"}, {"US", "teen"}] do
        user = user_fixture()

        {:ok, updated} =
          Gamend.Accounts.set_user_age(user, %{
            "birth_year" => Date.utc_today().year - 14,
            "birth_month" => 1,
            "age_country" => country,
            "age_method" => "self_declared"
          })

        assert updated.account_class == expected
      end
    end

    test "raising your age without a stronger signal is refused" do
      user = user_fixture()

      {:ok, child} =
        Gamend.Accounts.set_user_age(user, %{
          "birth_year" => 2016,
          "birth_month" => 1,
          "age_country" => "RO",
          "age_method" => "self_declared"
        })

      assert {:error, :age_change_not_allowed} =
               Gamend.Accounts.set_user_age(child, %{
                 "birth_year" => 1990,
                 "birth_month" => 1,
                 "age_country" => "RO",
                 "age_method" => "self_declared"
               })

      # ...but a platform signal outranks self-declaration.
      assert {:ok, adult} =
               Gamend.Accounts.set_user_age(child, %{
                 "birth_year" => 1990,
                 "birth_month" => 1,
                 "age_country" => "RO",
                 "age_method" => "platform_signal"
               })

      assert adult.account_class == "adult"
    end

    test "lowering your age never needs a stronger signal" do
      user = user_fixture()

      {:ok, adult} =
        Gamend.Accounts.set_user_age(user, %{
          "birth_year" => 1990,
          "birth_month" => 1,
          "age_country" => "RO",
          "age_method" => "self_declared"
        })

      assert {:ok, child} =
               Gamend.Accounts.set_user_age(adult, %{
                 "birth_year" => 2016,
                 "birth_month" => 1,
                 "age_country" => "RO",
                 "age_method" => "self_declared"
               })

      assert child.account_class == "child"
    end

    test "a malformed answer is refused rather than stored" do
      user = user_fixture()

      for attrs <- [
            %{"birth_month" => 3, "age_method" => "self_declared"},
            %{"birth_year" => "nineteen", "birth_month" => 3, "age_method" => "self_declared"}
          ] do
        assert {:error, :invalid_age} = Gamend.Accounts.set_user_age(user, attrs)
      end

      assert {:error, %Ecto.Changeset{}} =
               Gamend.Accounts.set_user_age(user, %{
                 "birth_year" => 2016,
                 "birth_month" => 13,
                 "age_method" => "self_declared"
               })
    end
  end

  describe "refresh_account_class/1" do
    test "graduation is a function of the calendar, not of an event" do
      # Nothing writes to a row on the day it turns 13. The stored class has to
      # be brought back in step by re-deriving it.
      user = user_fixture()
      this_year = Date.utc_today().year

      {:ok, child} =
        Gamend.Accounts.set_user_age(user, %{
          "birth_year" => this_year - 12,
          "birth_month" => 1,
          "age_country" => "US",
          "age_method" => "self_declared"
        })

      assert child.account_class == "child"

      # Age the row by a year without touching anything else.
      stale = %{child | birth_year: this_year - 13}
      {:ok, refreshed} = Gamend.Accounts.refresh_account_class(stale)

      assert refreshed.account_class == "teen"
    end
  end
end
