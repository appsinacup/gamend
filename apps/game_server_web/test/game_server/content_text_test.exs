defmodule GameServerWeb.ContentTextTest do
  @moduledoc """
  Quests and leaderboards used to store a translation per locale inside
  `metadata`. Editing a title left the copies behind, stale, with nothing to
  say which. These lock in the replacement rule: a row holds its source text
  and only its source text.
  """

  use ExUnit.Case, async: true

  alias GameServer.Leaderboards.Leaderboard
  alias GameServer.Quests.Quest
  alias GameServerWeb.ContentText

  describe "the database holds source text, never translations" do
    test "the per-locale lookup helpers are gone" do
      refute function_exported?(Quest, :localized_title, 2)
      refute function_exported?(Quest, :localized_description, 2)
      refute function_exported?(Leaderboard, :localized_title, 2)
      refute function_exported?(Leaderboard, :localized_description, 2)
    end

    test "so is the admin editor that wrote them" do
      refute Code.ensure_loaded?(GameServerWeb.AdminLive.TranslationMetadata)
    end

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
end
