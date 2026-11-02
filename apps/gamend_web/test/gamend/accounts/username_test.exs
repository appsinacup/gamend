defmodule Gamend.Accounts.UsernameTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Accounts.Username
  alias Gamend.Accounts.UsernameGenerator
  alias Gamend.AccountsFixtures

  setup do
    orig = Application.get_env(:gamend_core, :hooks_module)
    on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, orig) end)
    :ok
  end

  defmodule OverrideUsernameHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_user_register(_user, attrs),
      do: {:ok, Map.put(attrs, "username", "Custom.Handle#{System.unique_integer([:positive])}")}
  end

  defmodule InvalidUsernameHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_user_register(_user, attrs),
      do: {:ok, Map.put(attrs, "username", "!! not valid !!")}
  end

  defmodule VetoRegisterHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_user_register(_user, _attrs), do: {:error, :registration_vetoed}
  end

  defmodule PolicyHooks do
    use Gamend.TestSupport.NoopHooks

    # Letters of any mix, digits and `_`: looser than core on scripts, stricter
    # on separators. Generated `word-1234` handles fail it, so sign-up hands
    # out its own, as the hook's doc asks.
    @impl true
    def validate_username(handle) do
      if String.match?(handle, ~r/^[\p{L}\p{Nd}_]+$/u),
        do: :ok,
        else: {:error, "letters, digits and _ only"}
    end

    @impl true
    def before_user_register(_user, attrs),
      do: {:ok, Map.put(attrs, "username", "policy_#{System.unique_integer([:positive])}")}
  end

  defmodule DeferringHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def validate_username(_handle), do: :default
  end

  defp unique_device_id, do: "device-#{System.unique_integer([:positive])}"

  describe "generated usernames" do
    test "email registration gets a word-suffix username" do
      user = AccountsFixtures.unconfirmed_user_fixture()
      assert user.username =~ ~r/^[a-z]+-\d{4}$/
    end

    test "device registration gets a word-suffix username" do
      {:ok, user} = Accounts.find_or_create_from_device(unique_device_id())
      assert user.username =~ ~r/^[a-z]+-\d{4}$/
    end

    test "display name is slugified into the username" do
      {:ok, user} =
        Accounts.find_or_create_from_device(unique_device_id(), %{display_name: "Drágoș Test"})

      assert user.username =~ ~r/^dragos-test-\d{4}$/
    end

    test "explicit username in attrs is honored" do
      handle = "picked-#{System.unique_integer([:positive])}"

      {:ok, user} =
        Accounts.register_user(%{
          "email" => AccountsFixtures.unique_user_email(),
          "username" => handle
        })

      assert user.username == handle
    end
  end

  describe "before_user_register hook" do
    test "hook can override the username (lowercased on save)" do
      Application.put_env(:gamend_core, :hooks_module, OverrideUsernameHooks)

      user = AccountsFixtures.unconfirmed_user_fixture()
      assert user.username =~ ~r/^custom\.handle\d+$/
    end

    test "invalid hook username falls back to a generated one" do
      Application.put_env(:gamend_core, :hooks_module, InvalidUsernameHooks)

      user = AccountsFixtures.unconfirmed_user_fixture()
      assert user.username =~ ~r/^[a-z]+-\d+$/
    end

    test "hook can veto registration" do
      Application.put_env(:gamend_core, :hooks_module, VetoRegisterHooks)

      assert {:error, :registration_vetoed} =
               Accounts.register_user(%{"email" => AccountsFixtures.unique_user_email()})
    end
  end

  describe "update_username/2" do
    test "updates and lowercases a valid username" do
      user = AccountsFixtures.user_fixture()
      handle = "New.Handle#{System.unique_integer([:positive])}"

      assert {:ok, %User{} = updated} = Accounts.update_username(user, %{"username" => handle})
      assert updated.username == String.downcase(handle)
    end

    test "accepts one script of any alphabet, and Latin with Chinese, Japanese or Korean" do
      user = AccountsFixtures.user_fixture()

      for good <- [
            "nicö",
            "дмитрий",
            "山田太郎",
            "やまだ太郎",
            "ラーメン",
            "김민준",
            "δημήτρης",
            "tiệp",
            "مريم",
            "王wang",
            "小明abc",
            "yamada太郎",
            "taroやまだ",
            "김민준kim",
            "ㄅㄆㄇ王",
            "tom一号",
            "이민"
          ] do
        n = System.unique_integer([:positive])
        handle = good <> "-#{n}"
        assert {:ok, updated} = Accounts.update_username(user, %{"username" => handle})
        assert updated.username == handle
      end
    end

    test "normalizes fullwidth and decomposed forms onto one spelling" do
      user = AccountsFixtures.user_fixture()
      n = System.unique_integer([:positive])

      assert {:ok, updated} = Accounts.update_username(user, %{"username" => "ＤＲＡＧＯＳ#{n}"})
      assert updated.username == "dragos#{n}"

      decomposed = "s\u0326tefan#{n}"
      assert {:ok, updated} = Accounts.update_username(user, %{"username" => decomposed})
      assert updated.username == String.normalize(decomposed, :nfc)
      assert Accounts.get_user_by_username("S\u0326TEFAN#{n}").id == user.id
    end

    test "rejects a taken username" do
      taken = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Accounts.update_username(user, %{"username" => taken.username})

      assert {"has already been taken", _} = changeset.errors[:username]
    end

    test "rejects malformed usernames" do
      user = AccountsFixtures.user_fixture()

      for bad <- [
            "ab",
            "-leading",
            "trailing-",
            "two..dots",
            "spaced name",
            # Cyrillic а inside Latin: renders as "paypal"
            "pаypal",
            "ivanиван",
            "王иван",
            "abcمريم",
            "김민준やまだ",
            # an accent typed twice
            "cafe\u0301\u0301",
            "zero\u200Bwidth",
            "za\u0301\u0301\u0301\u0301\u0301lgo",
            "emoji😀"
          ] do
        result = Accounts.update_username(user, %{"username" => bad})
        assert {:error, changeset} = result
        assert Keyword.has_key?(changeset.errors, :username), "expected #{inspect(bad)} rejected"
      end
    end
  end

  describe "Username.default_rules/1" do
    test "names the rule a handle breaks" do
      assert Username.default_rules("王wang") == :ok
      assert {:error, "can only mix" <> _} = Username.default_rules("pаypal")
      assert {:error, "repeats or stacks" <> _} = Username.default_rules("cafe\u0301\u0301")
    end
  end

  describe "validate_username hook" do
    test "replaces core's rules; length, uniqueness and invisible characters stay" do
      Application.put_env(:gamend_core, :hooks_module, PolicyHooks)
      user = AccountsFixtures.user_fixture()
      n = System.unique_integer([:positive])

      # Latin with Cyrillic, which core refuses
      assert {:ok, updated} = Accounts.update_username(user, %{"username" => "ivanиван_#{n}"})
      assert updated.username == "ivanиван_#{n}"

      # a separator core allows
      assert {:error, changeset} =
               Accounts.update_username(user, %{"username" => "ivan.ivan#{n}"})

      assert {"letters, digits and _ only", _} = changeset.errors[:username]

      assert {:error, changeset} =
               Accounts.update_username(user, %{"username" => "zero\u200Bwidth"})

      assert {"has an invisible character", _} = changeset.errors[:username]

      assert {:error, changeset} = Accounts.update_username(user, %{"username" => "ab"})
      assert Keyword.has_key?(changeset.errors, :username)
    end

    test "the generator asks it, and sign-up uses the hook-supplied handle" do
      Application.put_env(:gamend_core, :hooks_module, PolicyHooks)

      assert UsernameGenerator.slug("Ivan Иван") == "ivan"
      assert UsernameGenerator.slug("Drágoș Țest") == nil

      {:ok, user} = Accounts.find_or_create_from_device(unique_device_id())
      assert user.username =~ ~r/^policy_\d+$/
    end

    test ":default keeps core's rules" do
      Application.put_env(:gamend_core, :hooks_module, DeferringHooks)
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} = Accounts.update_username(user, %{"username" => "pаypal"})
      assert {"can only mix" <> _, _} = changeset.errors[:username]
    end
  end

  test "get_user_by_username/1 is case-insensitive" do
    user = AccountsFixtures.user_fixture()

    found = Accounts.get_user_by_username(String.upcase(user.username))
    assert found && found.id == user.id
    refute Accounts.get_user_by_username("no-such-user-0000")
  end

  describe "UsernameGenerator.slug/1" do
    test "transliterates and normalizes" do
      assert UsernameGenerator.slug("Drágoș  Țest") == "dragos-test"
      assert UsernameGenerator.slug("A_B..C") == "a_b-c"
    end

    test "keeps a script that does not transliterate" do
      assert UsernameGenerator.slug("山田 太郎") == "山田-太郎"
      assert UsernameGenerator.slug("Дмитрий") == "дмитрий"
    end

    test "a long non-Latin name still generates a valid username" do
      {:ok, user} =
        Accounts.find_or_create_from_device(unique_device_id(), %{
          display_name: String.duplicate("山田太郎", 12)
        })

      assert user.username =~ ~r/^山田太郎.*-\d{4}$/u
      assert String.length(user.username) <= Gamend.Limits.get(:max_username)
    end

    test "returns nil when too little survives" do
      assert UsernameGenerator.slug(nil) == nil
      assert UsernameGenerator.slug("阿明") == nil
      # Mixed scripts: the ASCII half is what survives.
      assert UsernameGenerator.slug("Ivan Иван") == "ivan"
      assert UsernameGenerator.slug("--") == nil
    end
  end
end
