defmodule Gamend.QuestsRepeatCounterTest do
  @moduledoc """
  A `repeat` quest is one definition and one row that re-arms forever, so
  nothing about it says which run the player is on. `%{n}` in the title is how
  it does: the card reads "Treasures x 1", then "Treasures x 2".

  The number has to be worked out where a definition meets a player's row —
  writing it into the stored title would show every player the same one — and
  it has to stay *out* of the title until the string has been translated, since
  the title with the placeholder in it is the msgid. Both are pinned here.
  """
  use ExUnit.Case, async: true

  alias Gamend.Quests
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestProgress

  defp repeat(title, description \\ "d") do
    %Quest{reset: "repeat", title: title, description: description}
  end

  defp progress(claim_count, status \\ "active") do
    %QuestProgress{claim_count: claim_count, status: status}
  end

  # What an untranslated consumer (the JSON API) ends up showing.
  defp rendered(quest, progress) do
    quest |> Quests.resolve_counter(progress) |> Quests.render_counter()
  end

  test "no row yet reads as the first run" do
    assert rendered(repeat("Treasures x %{n}"), nil).title == "Treasures x 1"
  end

  test "an unclaimed row is the run in progress" do
    assert rendered(repeat("Treasures x %{n}"), progress(0)).title == "Treasures x 1"
    assert rendered(repeat("Treasures x %{n}"), progress(3)).title == "Treasures x 4"
  end

  test "a claimed row keeps the number of the run just finished" do
    # The card must not renumber itself under the player between completing and
    # claiming — they claimed "Treasures x 1", so that is what it says until it
    # re-arms.
    assert rendered(repeat("Treasures x %{n}"), progress(1, "claimed")).title == "Treasures x 1"
    assert rendered(repeat("Treasures x %{n}"), progress(4, "claimed")).title == "Treasures x 4"
  end

  test "a claimed row that somehow never counted still reads as run 1, never 0" do
    assert rendered(repeat("Treasures x %{n}"), progress(0, "claimed")).title == "Treasures x 1"
  end

  test "a nil claim_count is treated as no claims" do
    assert rendered(repeat("Treasures x %{n}"), progress(nil)).title == "Treasures x 1"
  end

  test "the description takes the counter too" do
    quest = repeat("Treasures x %{n}", "Find treasure number %{n}.")
    resolved = rendered(quest, progress(2))

    assert resolved.title == "Treasures x 3"
    assert resolved.description == "Find treasure number 3."
  end

  test "resolving leaves the title alone — it is the msgid a translation is found by" do
    resolved = Quests.resolve_counter(repeat("Treasures x %{n}"), progress(3))

    assert resolved.counter == 4
    assert resolved.title == "Treasures x %{n}"
  end

  test "an unresolved counter renders as run 1" do
    # The anonymous catalog pairs no progress row, and a card reading
    # "Treasures x %{n}" is worse than one reading the run they would start.
    assert Quests.render_counter(repeat("Treasures x %{n}")).title == "Treasures x 1"
  end

  test "a repeat quest without the placeholder is untouched" do
    quest = repeat("Find the treasure")
    assert Quests.resolve_counter(quest, progress(7)) == quest
  end

  test "a non-repeat quest is untouched even if it carries the placeholder" do
    # Daily and never quests get a fresh row per period, so a repetition count
    # would be meaningless — the placeholder is not theirs to use.
    for reset <- ["never", "daily", "weekly"] do
      quest = %Quest{reset: reset, title: "Words x %{n}", description: "d"}
      assert Quests.resolve_counter(quest, progress(9)) == quest
    end
  end

  describe "counter_start and counter_step" do
    # A ladder that pays every 50 wins after 100: run 1 is "Wins x 150".
    defp ladder_tail do
      %Quest{
        reset: "repeat",
        title: "Wins x %{n}",
        description: "Win %{n} games",
        metadata: %{"counter_start" => 150, "counter_step" => 50}
      }
    end

    test "a repeat quest counts from start in steps" do
      assert rendered(ladder_tail(), nil).title == "Wins x 150"
      assert rendered(ladder_tail(), progress(0)).title == "Wins x 150"
      assert rendered(ladder_tail(), progress(2)).description == "Win 250 games"
      assert rendered(ladder_tail(), progress(2, "claimed")).title == "Wins x 200"
    end

    test "a step of a chain reads its own start, so every step shares one msgid" do
      quest = %Quest{reset: "never", title: "Wins x %{n}", metadata: %{"counter_start" => 30}}

      assert Quests.counter(quest) == 30

      assert Quests.render_counter(Quests.resolve_counter(quest, progress(0))).title ==
               "Wins x 30"
    end

    test "missing or bad settings read as 1" do
      assert Quests.counter(%Quest{title: "x %{n}"}) == 1
      assert Quests.counter(%Quest{title: "x %{n}", metadata: %{"counter_start" => "7"}}) == 1
      assert Quests.counter(%Quest{title: "x %{n}", metadata: %{"counter_start" => -3}}) == 1
    end
  end
end
