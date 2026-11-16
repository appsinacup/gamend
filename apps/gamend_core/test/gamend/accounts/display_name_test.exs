defmodule Gamend.Accounts.DisplayNameTest do
  @moduledoc """
  The two ways to name a user, and the fallbacks they do and do not take.

  Four inline chains were in use before these existed. The one that mattered
  most: parties built a notification's `sender_name` as `display_name || ""`,
  so an invite from a player who had never set a display name arrived from
  nobody.
  """
  use Gamend.DataCase

  alias Gamend.Accounts
  alias Gamend.Accounts.User

  defp user(attrs), do: struct(User, Map.merge(%{id: Ecto.UUID.generate()}, attrs))

  describe "display_name/1" do
    test "prefers the display name" do
      assert Accounts.display_name(user(%{display_name: "Ana", username: "drift-2378"})) == "Ana"
    end

    test "falls back to the username, never to the empty string" do
      assert Accounts.display_name(user(%{display_name: nil, username: "drift-2378"})) ==
               "drift-2378"

      assert Accounts.display_name(user(%{display_name: "", username: "drift-2378"})) ==
               "drift-2378"

      assert Accounts.display_name(user(%{display_name: "   ", username: "drift-2378"})) ==
               "drift-2378"
    end

    test "never falls back to the email or the id" do
      named = user(%{display_name: nil, username: nil, email: "a@example.com"})
      assert Accounts.display_name(named) == ""
    end

    test "nil is the empty string, not a crash" do
      assert Accounts.display_name(nil) == ""
    end
  end

  describe "display_label/1" do
    test "pairs the name with the handle when they differ" do
      assert Accounts.display_label(user(%{display_name: "Ana", username: "drift-2378"})) ==
               "Ana (drift-2378)"
    end

    test "does not repeat a name that is already the handle" do
      assert Accounts.display_label(user(%{display_name: "Ana", username: "ana"})) == "Ana"
    end

    test "is the handle alone when there is no display name" do
      assert Accounts.display_label(user(%{display_name: nil, username: "drift-2378"})) ==
               "drift-2378"
    end
  end

  describe "the party invite that started this" do
    test "an invite from a user with no display name names them by handle" do
      leader = Gamend.AccountsFixtures.user_fixture()
      {:ok, leader} = Accounts.update_user(leader, %{display_name: nil})

      assert Accounts.display_name(leader) == leader.username
      refute Accounts.display_name(leader) == ""
    end
  end
end
