defmodule Gamend.QuestCodesTest do
  @moduledoc """
  Redemption codes: a way to finish a `code_only` quest. The races are in
  `Gamend.QuestCodeRaceTest`.
  """

  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Quests
  alias Gamend.Quests.Codes
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestCode
  alias Gamend.Quests.QuestProgress

  defmodule VetoHook do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_quest_claim(_user_id, %{code_only: true}, progress) do
      send(Application.fetch_env!(:gamend_core, :quest_code_test_pid), {:hook, progress})
      {:error, "not for you"}
    end

    def before_quest_claim(_user_id, _quest, progress), do: {:ok, progress}
  end

  defmodule DeleteQuestHook do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_quest_claim(_user_id, quest, progress) do
      {:ok, _} = Gamend.Quests.delete_quest(quest)
      {:ok, progress}
    end
  end

  defp code_quest(attrs \\ %{}) do
    defaults = %{
      key: "code_#{System.unique_integer([:positive])}",
      title: "Spring gift",
      code_only: true,
      rewards: [%{type: "currency", code: "gold", amount: 100}]
    }

    {:ok, quest} = Quests.create_quest(Map.merge(defaults, attrs))
    quest
  end

  defp code(quest, attrs \\ %{}) do
    {:ok, code} =
      Quests.create_code(
        quest,
        Map.merge(%{token: "T#{System.unique_integer([:positive])}"}, attrs)
      )

    code
  end

  defp user, do: AccountsFixtures.user_fixture()

  defp guest do
    {:ok, guest} = Accounts.find_or_create_from_device("code_test_#{System.unique_integer()}")
    guest
  end

  defp gold(user), do: Economy.balance(user.id, "gold")

  defp with_veto_hook do
    previous = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, VetoHook)
    Application.put_env(:gamend_core, :quest_code_test_pid, self())

    on_exit(fn ->
      Application.put_env(:gamend_core, :hooks_module, previous)
      Application.delete_env(:gamend_core, :quest_code_test_pid)
    end)
  end

  defp require_account_to_claim do
    previous = Application.get_env(:gamend_core, Gamend.AccountRequired, [])
    Application.put_env(:gamend_core, Gamend.AccountRequired, [:quest_claims])
    on_exit(fn -> Application.put_env(:gamend_core, Gamend.AccountRequired, previous) end)
  end

  describe "a code-only quest" do
    test "needs no objectives" do
      assert %Quest{code_only: true, objectives: []} = code_quest()
    end

    test "refuses a code_only that is not true or false" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Quests.create_quest(%{
                 key: "null_code_only",
                 title: "x",
                 code_only: nil,
                 objectives: [%{event: "e", target: 1}]
               })

      assert %{code_only: [_]} = errors_on(changeset)
    end

    test "a quest that is not one still needs them" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Quests.create_quest(%{key: "needs_objectives", title: "x"})

      assert %{objectives: [_]} = errors_on(changeset)
    end

    for {field, value, message} <- [
          {:reset, "daily", "must be \"never\""},
          {:objectives, [%{event: "won", target: 1}], "must be empty"},
          {:group_key, "a_group", "must be empty"},
          {:prerequisite_quest_key, "another", "must be empty"}
        ] do
      test "refuses #{field}" do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Quests.create_quest(%{
                   :key => "bad_code_quest",
                   :title => "x",
                   :code_only => true,
                   unquote(field) => unquote(Macro.escape(value))
                 })

        assert [error] = errors_on(changeset)[unquote(field)]
        assert error =~ unquote(message)
      end
    end
  end

  describe "normalize/1" do
    test "folds full-width forms, case, spaces, dashes and what a paste brings" do
      for typed <- ["ＡＢＣ－１２３", "abc 123", "ABC-123", " a​bc–12\u00003 ", "ＡＢＣ　１２３"] do
        assert QuestCode.normalize(typed) == "abc123", "#{inspect(typed)} did not normalize"
      end
    end

    test "keeps any language" do
      assert QuestCode.normalize("春节 快乐") == "春节快乐"
    end
  end

  describe "create_code/2" do
    test "a token is taken across quests, however it is typed" do
      code(code_quest(), %{token: "ABC-123"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Quests.create_code(code_quest(), %{token: "abc 123"})

      assert %{token: [_]} = errors_on(changeset)
    end

    test "refuses a quest that is not code-only" do
      {:ok, quest} =
        Quests.create_quest(%{key: "plain", title: "x", objectives: [%{event: "e", target: 1}]})

      assert {:error, :not_code_only} = Quests.create_code(quest, %{token: "ABC"})
    end

    test "refuses a token that is only spaces and dashes, or too long" do
      quest = code_quest()

      assert {:error, blank} = Quests.create_code(quest, %{token: " - - "})
      assert %{token: [_]} = errors_on(blank)

      assert {:error, long} = Quests.create_code(quest, %{token: String.duplicate("a", 129)})
      assert %{token: [_]} = errors_on(long)
    end

    test "takes what a paste brings out of the token" do
      {:ok, code} = Quests.create_code(code_quest(), %{token: " AB\u0000C\u200B "})

      assert code.token == "ABC"
      assert code.lookup == "abc"
    end

    test "refuses metadata that is null, and uses the column cannot hold" do
      quest = code_quest()

      assert {:error, null} = Quests.create_code(quest, %{token: "A", metadata: nil})
      assert %{metadata: [_]} = errors_on(null)

      assert {:error, big} = Quests.create_code(quest, %{token: "B", max_uses: 2_147_483_648})
      assert %{max_uses: [_]} = errors_on(big)
    end

    test "refuses uses below 1" do
      assert {:error, changeset} = Quests.create_code(code_quest(), %{token: "A", max_uses: 0})
      assert %{max_uses: [_]} = errors_on(changeset)
    end
  end

  describe "generate_codes/3" do
    test "makes that many distinct codes in the shown format" do
      quest = code_quest()

      assert {:ok, 600} =
               Quests.generate_codes(quest, 600, max_uses: 2, metadata: %{"source" => "stream"})

      codes = Codes.all(quest.key)
      assert length(codes) == 600
      assert codes |> Enum.map(& &1.lookup) |> Enum.uniq() |> length() == 600

      for code <- codes do
        assert code.token =~ ~r/^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){3}$/
        assert code.max_uses == 2
        assert code.uses == 0
        assert code.metadata == %{"source" => "stream"}
      end
    end

    test "nil uses means every player once" do
      quest = code_quest()
      assert {:ok, 1} = Quests.generate_codes(quest, 1, max_uses: nil)
      assert [%{max_uses: nil}] = Codes.all(quest.key)
    end

    test "refuses what it cannot make" do
      quest = code_quest()

      assert {:error, :invalid_count} = Quests.generate_codes(quest, 0)
      assert {:error, :too_many_codes} = Quests.generate_codes(quest, 10_001)
      assert {:error, %Ecto.Changeset{}} = Quests.generate_codes(quest, 1, max_uses: 0)
      assert Codes.all(quest.key) == []
    end

    test "refuses a quest that is not code-only" do
      {:ok, quest} =
        Quests.create_quest(%{key: "plain2", title: "x", objectives: [%{event: "e", target: 1}]})

      assert {:error, :not_code_only} = Quests.generate_codes(quest, 1)
    end
  end

  describe "redeem_code/2" do
    test "finishes the quest and pays it at once" do
      quest = code_quest()
      code = code(quest, %{metadata: %{"source" => "stream"}})
      player = user()

      assert {:ok, %{progress: progress, rewards: [reward]}} =
               Quests.redeem_code(player.id, code.token)

      assert progress.status == "claimed"
      assert progress.code_id == code.id
      assert progress.metadata == %{"source" => "stream"}
      assert reward.amount == 100
      assert gold(player) == 100
      assert Codes.get(code.id).uses == 1
    end

    test "the token may be typed any way" do
      quest = code_quest()
      code(quest, %{token: "ABC-123"})

      assert {:ok, _} = Quests.redeem_code(user().id, "ａｂｃ　１２３")
    end

    test "a generated code typed with look-alike letters still redeems" do
      quest = code_quest()
      code(quest, %{token: "ABCD-0011-QRST"})
      # An admin's own token keeps its letters, and its exact form wins.
      code(quest, %{token: "GOLD"})

      assert {:ok, _} = Quests.redeem_code(user().id, "abcd-0oIl-qrst")
      assert %QuestCode{token: "GOLD"} = Codes.find("gold")
      assert [%{token: "ABCD-0011-QRST"}] = Quests.list_codes(quest.key, search: "ABCD OOLL QRST")
    end

    test "an uncapped code's redeems leave its row alone, and its uses are counted" do
      quest = code_quest()
      code = code(quest, %{max_uses: nil})
      stored = Repo.get!(QuestCode, code.id)

      {:ok, _} = Quests.redeem_code(user().id, code.token)
      {:ok, _} = Quests.redeem_code(user().id, code.token)

      assert Repo.get!(QuestCode, code.id) == stored
      assert Codes.get(code.id).uses == 2
      assert [%{uses: 2}] = Quests.list_codes(quest.key)
      assert [%{uses: 2}] = Codes.all(quest.key)

      {:ok, _} = Quests.set_code_status(code.id, "revoked")
      assert {:error, :code_not_found} = Quests.redeem_code(user().id, code.token)
    end

    test "a key that pays nothing opens the gate" do
      quest = code_quest(%{key: "beta_access", rewards: []})
      code = code(quest)
      player = user()

      assert Quests.get_progress(player.id, "beta_access") == nil
      assert {:ok, %{rewards: []}} = Quests.redeem_code(player.id, code.token)
      assert %QuestProgress{} = Quests.get_progress(player.id, "beta_access")
    end

    test "one answer for every miss" do
      revoked = code(code_quest())
      {:ok, _} = Quests.set_code_status(revoked.id, "revoked")

      inactive = code(code_quest(%{active: false}))

      ended =
        code(
          code_quest(%{
            starts_at: DateTime.add(DateTime.utc_now(), -7200),
            ends_at: DateTime.add(DateTime.utc_now(), -3600)
          })
        )

      not_yet = code(code_quest(%{starts_at: DateTime.add(DateTime.utc_now(), 3600)}))

      used_up = code(code_quest(), %{max_uses: 1})
      assert {:ok, _} = Quests.redeem_code(user().id, used_up.token)

      player = user()

      for token <-
            ["nope", "", " - ", revoked.token, inactive.token, ended.token] ++
              [not_yet.token, used_up.token, String.duplicate("a", 5000)] do
        assert {:error, :code_not_found} = Quests.redeem_code(player.id, token)
      end

      assert gold(player) == 0
    end

    test "a player redeems a quest once, by any of its codes, and spends no second use" do
      quest = code_quest()
      first = code(quest)
      second = code(quest)
      player = user()

      assert {:ok, _} = Quests.redeem_code(player.id, first.token)
      assert {:error, :already_redeemed} = Quests.redeem_code(player.id, first.token)
      assert {:error, :already_redeemed} = Quests.redeem_code(player.id, second.token)

      assert gold(player) == 100
      assert Codes.get(first.id).uses == 1
      assert Codes.get(second.id).uses == 0
    end

    test "a shared code pays each player once, up to its cap" do
      quest = code_quest()
      code = code(quest, %{max_uses: 2})

      assert {:ok, _} = Quests.redeem_code(user().id, code.token)
      assert {:ok, _} = Quests.redeem_code(user().id, code.token)
      assert {:error, :code_not_found} = Quests.redeem_code(user().id, code.token)
    end

    test "restoring a revoked code makes it work again" do
      code = code(code_quest())
      {:ok, _} = Quests.set_code_status(code.id, "revoked")
      {:ok, _} = Quests.set_code_status(code.id, "active")

      assert {:ok, _} = Quests.redeem_code(user().id, code.token)
    end

    test "a guest may redeem a shared code" do
      code = code(code_quest(), %{max_uses: nil})
      player = guest()

      assert {:ok, _} = Quests.redeem_code(player.id, code.token)
      assert gold(player) == 100
    end

    test "a guest is refused when the host requires an account to claim" do
      require_account_to_claim()
      code = code(code_quest())
      player = guest()

      assert {:error, :account_required} = Quests.redeem_code(player.id, code.token)
      assert Codes.get(code.id).uses == 0
      assert {:ok, _} = Quests.redeem_code(user().id, code.token)
    end

    test "the hook may refuse, sees the code, and a refusal spends nothing" do
      with_veto_hook()
      code = code(code_quest(), %{metadata: %{"source" => "stream"}})
      player = user()

      assert {:error, {:hook_rejected, "not for you"}} = Quests.redeem_code(player.id, code.token)

      code_id = code.id
      assert_received {:hook, %QuestProgress{id: nil, code_id: ^code_id} = pending}
      assert pending.metadata == %{"source" => "stream"}

      assert Codes.get(code.id).uses == 0
      refute Repo.exists?(from p in QuestProgress, where: p.user_id == ^player.id)
    end

    test "a quest deleted since the code was read is a miss" do
      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, DeleteQuestHook)
      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)

      code = code(code_quest())

      assert {:error, :code_not_found} = Quests.redeem_code(user().id, code.token)
    end

    test "survives a guest signing in, code included" do
      quest = code_quest()
      code = code(quest)
      player = guest()
      account = user()

      {:ok, _} = Quests.redeem_code(player.id, code.token)
      assert Quests.merge_user_progress(player.id, account.id) == 1

      assert %QuestProgress{code_id: code_id} = Quests.get_progress(account.id, quest.key)
      assert code_id == code.id
    end

    test "a used code stays usable as proof after its quest's window closes" do
      quest = code_quest(%{ends_at: DateTime.add(DateTime.utc_now(), 3600)})
      code = code(quest)
      player = user()

      {:ok, _} = Quests.redeem_code(player.id, code.token)

      {:ok, _} = Quests.update_quest(quest, %{active: false})
      assert %QuestProgress{} = Quests.get_progress(player.id, quest.key)
    end
  end

  describe "code_open?/1" do
    test "says whether a code would be accepted" do
      code = code(code_quest(), %{max_uses: 1})

      assert Quests.code_open?(code.token)
      refute Quests.code_open?("nope")

      {:ok, _} = Quests.redeem_code(user().id, code.token)
      refute Quests.code_open?(code.token)
    end
  end

  describe "who sees a code-only quest" do
    test "a player, only once redeemed" do
      quest = code_quest()
      code = code(quest)
      player = user()

      refute Enum.any?(Quests.list_user_quests(player.id), &(&1.quest.key == quest.key))
      assert Quests.count_user_quests(player.id) == 0

      {:ok, _} = Quests.redeem_code(player.id, code.token)

      assert [%{quest: %{key: key}, claimable: false}] = Quests.list_user_quests(player.id)
      assert key == quest.key
    end

    test "nobody signed out" do
      quest = code_quest(%{category: "secret"})

      refute Enum.any?(Quests.catalog(), &(&1.key == quest.key))
      refute "secret" in Quests.visible_categories(nil)
    end

    test "events do not reach it" do
      quest = code_quest()
      assert {:ok, []} = Quests.report_event(user().id, "anything")
      assert Quests.funnel(quest.key) == %{}
    end
  end

  describe "redeemable/2" do
    test "lists the open ones, with the viewer's row" do
      quest = code_quest()
      code = code(quest)
      other = code_quest()
      player = user()

      assert %{total: 2, entries: entries} = Quests.redeemable(player.id)
      assert Enum.all?(entries, &is_nil(&1.progress))

      {:ok, _} = Quests.redeem_code(player.id, code.token)

      %{entries: entries} = Quests.redeemable(player.id)
      assert %{progress: %QuestProgress{}} = Enum.find(entries, &(&1.quest.key == quest.key))
      assert %{progress: nil} = Enum.find(entries, &(&1.quest.key == other.key))
    end

    test "works signed out, and narrows to one" do
      quest = code_quest()
      code_quest()

      assert %{total: 2} = Quests.redeemable(nil)
      assert %{total: 1, entries: [entry]} = Quests.redeemable(nil, quest: quest.key)
      assert entry.quest.key == quest.key
      assert %{total: 0} = Quests.redeemable(nil, quest: "nothing_by_this_key")
    end

    test "leaves out quests that are not open, or not code-only" do
      code_quest(%{active: false})
      code_quest(%{starts_at: DateTime.add(DateTime.utc_now(), 3600)})

      {:ok, _} =
        Quests.create_quest(%{key: "plain3", title: "x", objectives: [%{event: "e", target: 1}]})

      assert %{total: 0} = Quests.redeemable(nil)
      refute Quests.any_redeemable?()
    end

    test "a hidden quest is off the list until redeemed, and its codes work" do
      quest = code_quest(%{hidden: true})
      code = code(quest)
      player = user()

      assert %{total: 0} = Quests.redeemable(player.id)
      assert %{total: 0} = Quests.redeemable(player.id, quest: quest.key)
      refute Quests.any_redeemable?()

      {:ok, _} = Quests.redeem_code(player.id, code.token)

      assert %{total: 1} = Quests.redeemable(player.id)
    end
  end

  describe "the admin's view" do
    test "search is exact, however it is typed" do
      quest = code_quest()
      code(quest, %{token: "ABC-123"})
      code(quest, %{token: "ABC-1234"})

      assert [%{token: "ABC-123"}] = Quests.list_codes(quest.key, search: "abc 123")
      assert Quests.count_codes(quest.key, search: "abc 123") == 1
      assert Quests.count_codes(quest.key) == 2
    end

    test "pages" do
      quest = code_quest()
      for _ <- 1..3, do: code(quest)

      assert length(Quests.list_codes(quest.key, page: 1, page_size: 2)) == 2
      assert length(Quests.list_codes(quest.key, page: 2, page_size: 2)) == 1
    end

    test "says who used a code" do
      code = code(code_quest(), %{max_uses: nil})
      first = user()
      second = user()

      {:ok, _} = Quests.redeem_code(first.id, code.token)
      {:ok, _} = Quests.redeem_code(second.id, code.token)

      assert code.id |> Codes.used_by() |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([first.id, second.id])

      assert [_] = Codes.used_by(code.id, 1)
    end

    test "says who used each code of a page in one go, first redeemers first" do
      quest = code_quest()
      shared = code(quest, %{max_uses: nil})
      single = code(quest)
      unused = code(quest)
      [a, b, c] = for _ <- 1..3, do: user()

      for player <- [a, b, c], do: {:ok, _} = Quests.redeem_code(player.id, shared.token)
      {:ok, _} = Quests.redeem_code(user().id, single.token)

      used = Codes.used_by_codes([shared.id, single.id, unused.id], 2)

      assert Enum.map(used[shared.id], & &1.id) == [a.id, b.id]
      assert [_] = used[single.id]
      refute Map.has_key?(used, unused.id)
      assert Codes.used_by_codes([]) == %{}
    end

    test "the export reads every code in batches, oldest first" do
      quest = code_quest()
      codes = for _ <- 1..5, do: code(quest)

      assert quest.key |> Codes.stream_all(2) |> Enum.map(& &1.id) ==
               Enum.map(Codes.all(quest.key), & &1.id)

      assert quest.key |> Codes.stream_all(2) |> Enum.count() == length(codes)
    end

    test "set_code_status/2 refuses what is not there" do
      assert {:error, :code_not_found} =
               Quests.set_code_status(Gamend.UUIDv7.generate(), "revoked")

      assert {:error, :code_not_found} = Quests.set_code_status("not-a-uuid", "revoked")
      assert {:error, :invalid_state} = Quests.set_code_status(Gamend.UUIDv7.generate(), "nope")
    end

    test "deleting the quest takes its codes" do
      quest = code_quest()
      code = code(quest)

      {:ok, _} = Quests.delete_quest(quest)

      assert Codes.get(code.id) == nil
    end
  end
end
