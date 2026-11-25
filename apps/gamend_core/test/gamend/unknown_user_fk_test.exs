defmodule Gamend.UnknownUserFkTest do
  @moduledoc """
  Writing a row that points at a user who does not exist.

  Left to the database, these raise `Ecto.ConstraintError`, so an admin
  request naming a stale id, or a plugin passing one, would come back 500. The
  schemas declare `foreign_key_constraint(:user_id)`, but SQLite (the default
  adapter) does not report *which* constraint an INSERT violated, so Ecto
  cannot match the declaration and raises instead of returning a changeset.
  The adapter's own docs say `foreign_key_constraint/3` "may not work at all"
  there.

  So the contexts check first. The constraint stays declared: it is still the
  thing that makes the row impossible, and on Postgres it still reports.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Economy
  alias Gamend.Economy.Wallet
  alias Gamend.Inventory
  alias Gamend.Leaderboards
  alias Gamend.Repo

  import Ecto.Query, only: [from: 2]

  setup do
    {:ok, board} =
      Leaderboards.create_leaderboard(%{
        "slug" => "unknown_user_#{System.unique_integer([:positive])}",
        "title" => "Unknown User Test"
      })

    %{board: board, ghost: Ecto.UUID.generate()}
  end

  describe "an id that belongs to no account" do
    test "submitting a score answers instead of raising", %{board: board, ghost: ghost} do
      assert Leaderboards.submit_score(board.id, ghost, 10) == {:error, :user_not_found}
    end

    test "granting and spending currency answer instead of raising", %{ghost: ghost} do
      assert Economy.grant(ghost, "gold", 10) == {:error, :user_not_found}
      assert Economy.spend(ghost, "gold", 10) == {:error, :user_not_found}
    end

    test "granting and consuming items answer instead of raising", %{ghost: ghost} do
      assert Inventory.grant_item(ghost, "sword", 1) == {:error, :user_not_found}
      assert Inventory.consume_item(ghost, "sword", 1) == {:error, :user_not_found}
    end
  end

  describe "a malformed id" do
    test "is not found rather than an Ecto.Query.CastError", %{board: board} do
      assert Leaderboards.submit_score(board.id, "not-a-uuid", 10) == {:error, :user_not_found}
      assert Economy.grant("not-a-uuid", "gold", 10) == {:error, :user_not_found}
    end
  end

  describe "a row deleted between the check and the write" do
    # The contexts check first, but the check and the INSERT are not one
    # statement. `Gamend.Repo.rescue_foreign_key/2` answers for the window.

    test "a ledger write for a vanished user answers user_not_found", %{ghost: ghost} do
      insert_wallet = fn ->
        %Wallet{}
        |> Wallet.changeset(%{user_id: ghost, currency: "gold", balance: 1})
        |> Repo.insert()
        |> case do
          {:ok, _} -> {:ok, 1}
          {:error, changeset} -> {:error, changeset}
        end
      end

      assert Gamend.Ledger.change(insert_wallet, fn _ -> :ok end, fn -> 0 end) ==
               {:error, :user_not_found}
    end

    test "a score for a board deleted after its check answers leaderboard_not_found",
         %{board: board} do
      user = Gamend.AccountsFixtures.user_fixture()
      Leaderboards.invalidate_cache()

      # Delete the board the moment the context has read it, so its check
      # passes and the INSERT is the first thing to notice.
      handler = {__MODULE__, :delete_board_after_read, System.unique_integer()}

      :telemetry.attach(
        handler,
        [:gamend, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if meta[:source] == "leaderboards" and !Process.get(:board_deleted) do
            Process.put(:board_deleted, true)
            Repo.delete_all(from l in Leaderboards.Leaderboard, where: l.id == ^board.id)
          end
        end,
        nil
      )

      result = Leaderboards.submit_score(board.id, user.id, 10)
      :telemetry.detach(handler)

      assert Process.get(:board_deleted)
      assert result == {:error, :leaderboard_not_found}
    end

    test "only foreign keys are answered; other constraint errors still raise" do
      changeset = Ecto.Changeset.change(%Wallet{})

      raise_unique = fn ->
        raise Ecto.ConstraintError,
          type: :unique,
          constraint: "wallets_user_id_currency_index",
          changeset: changeset,
          action: :insert
      end

      assert_raise Ecto.ConstraintError, fn -> Repo.rescue_foreign_key(:gone, raise_unique) end
      assert Repo.rescue_foreign_key(:gone, fn -> {:ok, :written} end) == {:ok, :written}
    end
  end

  describe "a real user is unaffected" do
    test "the happy paths still write", %{board: board} do
      user = Gamend.AccountsFixtures.user_fixture()

      assert {:ok, record} = Leaderboards.submit_score(board.id, user.id, 42)
      assert record.score == 42

      assert {:ok, 10} = Economy.grant(user.id, "gold", 10)
      assert {:ok, 1} = Inventory.grant_item(user.id, "sword", 1)
    end
  end
end
