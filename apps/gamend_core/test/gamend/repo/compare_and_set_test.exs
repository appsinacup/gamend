defmodule Gamend.Repo.CompareAndSetTest do
  use Gamend.DataCase, async: true

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures

  setup do
    user =
      AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(display_name: "Before")
      |> Repo.update!()

    %{user: user}
  end

  test "writes while the precondition holds and answers the row as written", %{user: user} do
    assert {:ok, %User{} = written} =
             from(u in User, where: u.id == ^user.id and u.display_name == "Before")
             |> Repo.compare_and_set(set: [display_name: "After"])

    assert written.id == user.id
    assert written.display_name == "After"
    assert Repo.get!(User, user.id).display_name == "After"
  end

  test "changes nothing once the precondition no longer holds", %{user: user} do
    query = from(u in User, where: u.id == ^user.id and u.display_name == "Before")

    assert {:ok, _} = Repo.compare_and_set(query, set: [display_name: "First"])

    assert {:error, :precondition_failed} =
             Repo.compare_and_set(query, set: [display_name: "Second"])

    assert Repo.get!(User, user.id).display_name == "First"
  end

  test "a query that does not pin one row is a bug", %{user: user} do
    other = AccountsFixtures.user_fixture()

    assert_raise ArgumentError, ~r/updated 2 rows/, fn ->
      from(u in User, where: u.id in ^[user.id, other.id])
      |> Repo.compare_and_set(set: [display_name: "Both"])
    end
  end
end
