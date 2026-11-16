defmodule GamendWeb.ContentTextTest do
  @moduledoc """
  Quests and leaderboards used to store a translation per locale inside
  `metadata`. Editing a title left the copies behind, stale, with nothing to
  say which. These lock in the replacement rule: a row holds its source text
  and only its source text.
  """

  use ExUnit.Case, async: true

  alias Gamend.Quests.Quest
  alias GamendWeb.ContentText

  describe "the database holds source text, never translations" do
    test "metadata is not consulted when rendering" do
      quest = %Quest{
        title: "Welcome aboard",
        description: "Log in for the first time.",
        metadata: %{"titles" => %{"ro" => "STALE COPY"}}
      }

      translated = ContentText.translate(quest)

      refute translated.title == "STALE COPY"
      assert translated.metadata == quest.metadata, "metadata is data, not a translation source"
    end
  end

  describe "translate/1" do
    test "an untranslated string falls back to itself" do
      assert ContentText.t("Winter Cup 2026") == "Winter Cup 2026"
    end

    test "nil and empty pass through" do
      assert ContentText.t(nil) == nil
      assert ContentText.t("") == ""
    end

    test "walks lists and entry maps, leaving other fields alone" do
      entries = [
        %{quest: %Quest{title: "Night owl", description: nil}, progress: 3}
      ]

      [entry] = ContentText.translate(entries)

      assert entry.progress == 3
      assert is_binary(entry.quest.title)
    end

    test "leaves anything without the fields untouched" do
      assert ContentText.translate(:not_a_record) == :not_a_record
      assert ContentText.translate(42) == 42
    end
  end

  describe "a repeat quest's %{n}" do
    test "is interpolated from the resolved counter, not left on the page" do
      quest = %Quest{title: "Treasures x %{n}", description: "Find number %{n}.", counter: 3}

      translated = ContentText.translate(quest)

      assert translated.title == "Treasures x 3"
      assert translated.description == "Find number 3."
    end

    test "reads as run 1 with no counter, rather than rendering the placeholder" do
      quest = %Quest{title: "Treasures x %{n}", description: ""}

      assert ContentText.translate(quest).title == "Treasures x 1"
    end

    test "never logs a missing binding" do
      # The anonymous quest catalog pairs no progress row, so this used to log
      # `missing Gettext bindings: [:n]` on every page view in a locale that
      # had the string translated.
      quest = %Quest{title: "Treasures x %{n}", description: "Find number %{n}."}

      log = ExUnit.CaptureLog.capture_log(fn -> ContentText.translate(quest) end)

      refute log =~ "missing Gettext bindings"
    end
  end
end
