defmodule Gamend.MatchSeatingTest do
  use ExUnit.Case, async: true

  alias Gamend.MatchSeating

  @ticket %{max_players: 4, match_params: %{"mode" => "duel"}}

  describe "misspelt answers raise where they are written" do
    test "a lobby option" do
      assert_raise ArgumentError, fn -> MatchSeating.new_lobby(max_user: 3) end
    end

    test "an ask option" do
      assert_raise ArgumentError, fn -> MatchSeating.in_lobby("id", accept_after: 3) end
    end

    test "default takes no lobby options" do
      assert_raise ArgumentError, fn -> MatchSeating.default(max_users: 3) end
    end

    test "a time that is not a positive integer" do
      assert_raise ArgumentError, fn -> MatchSeating.default(accept_timeout_ms: 0) end
    end
  end

  describe "lobby_attrs/2" do
    test "what is left out is core's: hidden, locked, hostless, sized to the match" do
      assert %{max_users: 4, is_hidden: true, is_locked: true, hostless: true} =
               MatchSeating.lobby_attrs(MatchSeating.new_lobby(), @ticket)
    end

    test "the game's settings win" do
      seating = MatchSeating.new_lobby(max_users: 9, is_hidden: false, title: "Arena")

      assert %{max_users: 9, is_hidden: false, title: "Arena"} =
               MatchSeating.lobby_attrs(seating, @ticket)
    end

    test "naming a host makes it hosted" do
      seating = MatchSeating.new_lobby(host_id: "someone")

      assert %{host_id: "someone", hostless: false} = MatchSeating.lobby_attrs(seating, @ticket)
    end

    test "always locked at birth, opened after only when asked" do
      open = MatchSeating.new_lobby(is_locked: false)

      assert %{is_locked: true} = MatchSeating.lobby_attrs(open, @ticket)
      assert MatchSeating.unlock?(open)
      refute MatchSeating.unlock?(MatchSeating.new_lobby())
      refute MatchSeating.unlock?(MatchSeating.default())
    end
  end

  describe "dump/1 and load/1" do
    defp through_json(seating) do
      seating |> MatchSeating.dump() |> Jason.encode!() |> Jason.decode!() |> MatchSeating.load()
    end

    test "a named lobby survives JSON" do
      assert through_json(MatchSeating.in_lobby("room")).lobby_id == "room"
    end

    test "new-lobby settings survive JSON, with atom keys" do
      seating = MatchSeating.new_lobby(max_users: 9, title: "Arena", is_locked: false)
      loaded = through_json(seating)

      assert loaded.lobby == %{max_users: 9, title: "Arena", is_locked: false}
      assert MatchSeating.unlock?(loaded)
    end

    test "a stored field it does not know is not read" do
      stored = %{Atom.to_string(:lobby) => %{"password_hash" => "x", "title" => "Arena"}}

      assert MatchSeating.load(stored).lobby == %{title: "Arena"}
    end

    test "nothing stored is the default" do
      assert MatchSeating.load(nil) == MatchSeating.default()
    end

    test "the accept is not carried: it has been answered" do
      assert through_json(MatchSeating.default(accept_timeout_ms: 5)).accept_timeout_ms == nil
    end
  end
end
