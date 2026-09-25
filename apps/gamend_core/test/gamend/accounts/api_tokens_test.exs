defmodule Gamend.Accounts.ApiTokensTest do
  use Gamend.DataCase, async: true

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.ApiToken
  alias Gamend.Accounts.ApiTokens
  alias Gamend.AccountsFixtures

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  describe "create/2" do
    test "answers the token once and stores only its hash", %{user: user} do
      assert {:ok, "gamend_pat_" <> secret = token, row} =
               ApiTokens.create(user, %{"name" => "ci", "expires_in_days" => 30})

      assert byte_size(secret) >= 40
      assert row.name == "ci"
      assert row.hint == String.slice(secret, 0, 6)
      assert row.token_hash == :crypto.hash(:sha256, token)
      refute Repo.get!(ApiToken, row.id).token_hash == token
      assert DateTime.diff(row.expires_at, DateTime.utc_now(), :day) in 29..30
    end

    test "a token that never expires has no expires_at", %{user: user} do
      assert {:ok, _token, row} =
               ApiTokens.create(user, %{"name" => "forever", "expires_in_days" => nil})

      assert row.expires_at == nil
    end

    test "a name is required and the lifetime is one of the choices", %{user: user} do
      assert {:error, changeset} = ApiTokens.create(user, %{"name" => " "})
      assert "can't be blank" in errors_on(changeset).name

      assert {:error, changeset} =
               ApiTokens.create(user, %{"name" => "x", "expires_in_days" => 7})

      assert errors_on(changeset).expires_in_days != []
    end

    test "stops at the per-user limit", %{user: user} do
      # No other test reads this key, so the global override cannot leak.
      Gamend.SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_api_tokens_per_user, 1)

      on_exit(fn ->
        Gamend.SettingsHelpers.delete(:gamend_core, Gamend.Limits, :max_api_tokens_per_user)
      end)

      assert {:ok, _, _} = ApiTokens.create(user, %{"name" => "one"})
      assert {:error, :limit_reached} = ApiTokens.create(user, %{"name" => "two"})
    end
  end

  describe "verify/1" do
    test "a live token names its owner", %{user: user} do
      {:ok, token, row} = ApiTokens.create(user, %{"name" => "ci"})

      assert {:ok, verified, verified_row} = ApiTokens.verify(token)
      assert verified.id == user.id
      assert verified_row.id == row.id
    end

    test "unknown, malformed and JWT-shaped strings do not verify" do
      assert ApiTokens.verify("gamend_pat_nope") == :error
      assert ApiTokens.verify("eyJhbGciOi.x.y") == :error
      assert ApiTokens.verify(nil) == :error
    end

    test "an expired token does not verify", %{user: user} do
      {:ok, token, row} = ApiTokens.create(user, %{"name" => "old"})
      past = DateTime.utc_now() |> DateTime.add(-1, :minute) |> DateTime.truncate(:second)
      Repo.update_all(from(t in ApiToken, where: t.id == ^row.id), set: [expires_at: past])

      assert ApiTokens.verify(token) == :error
    end

    test "a revoked token does not verify", %{user: user} do
      {:ok, token, row} = ApiTokens.create(user, %{"name" => "gone"})

      assert {:ok, _} = ApiTokens.revoke(user.id, row.id)
      assert ApiTokens.verify(token) == :error
    end

    test "a credential change retires every token made before it", %{user: user} do
      {:ok, token, _row} = ApiTokens.create(user, %{"name" => "before"})

      {:ok, {user, _expired}} = Accounts.revoke_all_tokens(user)

      assert ApiTokens.verify(token) == :error

      {:ok, fresh, _row} = ApiTokens.create(user, %{"name" => "after"})
      assert {:ok, _, _} = ApiTokens.verify(fresh)
    end
  end

  test "revoke/2 only reaches the owner's tokens", %{user: user} do
    other = AccountsFixtures.user_fixture()
    {:ok, _token, row} = ApiTokens.create(other, %{"name" => "theirs"})

    assert ApiTokens.revoke(user.id, row.id) == {:error, :not_found}
    assert Repo.get(ApiToken, row.id)
  end

  test "list/2 and count/1 are the owner's, newest first", %{user: user} do
    {:ok, _, first} = ApiTokens.create(user, %{"name" => "first"})
    {:ok, _, second} = ApiTokens.create(user, %{"name" => "second"})
    {:ok, _, _} = ApiTokens.create(AccountsFixtures.user_fixture(), %{"name" => "not mine"})

    assert Enum.map(ApiTokens.list(user.id), & &1.id) == [second.id, first.id]
    assert ApiTokens.count(user.id) == 2
  end

  test "dead_query/0 finds expired and superseded tokens, and nothing live", %{user: user} do
    {:ok, _, live} = ApiTokens.create(user, %{"name" => "live"})
    {:ok, _, expired} = ApiTokens.create(user, %{"name" => "expired"})
    past = DateTime.utc_now() |> DateTime.add(-1, :minute) |> DateTime.truncate(:second)
    Repo.update_all(from(t in ApiToken, where: t.id == ^expired.id), set: [expires_at: past])

    other = AccountsFixtures.user_fixture()
    {:ok, _, superseded} = ApiTokens.create(other, %{"name" => "superseded"})
    {:ok, _} = Accounts.revoke_all_tokens(other)

    dead = ApiTokens.dead_query() |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

    assert dead == Enum.sort([expired.id, superseded.id])
    refute live.id in dead

    # Deletable on either adapter: no join at the top level.
    assert {2, _} = Repo.delete_all(ApiTokens.dead_query())
    assert Repo.get(ApiToken, live.id)
  end
end
