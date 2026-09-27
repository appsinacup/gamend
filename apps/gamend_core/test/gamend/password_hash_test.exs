defmodule Gamend.Accounts.PasswordHashTest do
  use Gamend.DataCase, async: true

  alias Gamend.Accounts
  alias Gamend.Accounts.PasswordHash

  @password "correct horse battery staple"

  describe "hash/1 and verify/2" do
    test "a fresh hash is Argon2id at the configured settings" do
      hash = PasswordHash.hash(@password)
      # Derived, not hardcoded: the suite runs these settings turned down.
      cfg = Application.get_env(:gamend_core, PasswordHash, [])
      m = Bitwise.bsl(1, Keyword.get(cfg, :argon2_memory_log2, 14))
      t = Keyword.get(cfg, :argon2_time_cost, 3)

      assert String.starts_with?(hash, "$argon2id$v=19$m=#{m},t=#{t},p=1$")
      assert PasswordHash.verify(@password, hash)
      refute PasswordHash.verify("wrong", hash)
    end

    test "a bcrypt hash written before the switch still verifies" do
      legacy = Bcrypt.hash_pwd_salt(@password)

      assert String.starts_with?(legacy, "$2")
      assert PasswordHash.verify(@password, legacy)
      refute PasswordHash.verify("wrong", legacy)
    end

    test "an unrecognised hash fails the login instead of raising" do
      refute PasswordHash.verify(@password, "not-a-hash")
      refute PasswordHash.verify(@password, "")
    end
  end

  describe "needs_rehash?/1" do
    test "true for bcrypt, false for a current Argon2id hash" do
      assert PasswordHash.needs_rehash?(Bcrypt.hash_pwd_salt(@password))
      refute PasswordHash.needs_rehash?(PasswordHash.hash(@password))
    end

    test "true for Argon2id written at different settings" do
      # Same algorithm, different parameters — still due an upgrade.
      cfg = Application.get_env(:gamend_core, PasswordHash, [])
      m = Keyword.get(cfg, :argon2_memory_log2, 14)
      weaker = Argon2.hash_pwd_salt(@password, t_cost: 1, m_cost: m + 1, parallelism: 1)

      assert String.starts_with?(weaker, "$argon2id$")
      assert PasswordHash.needs_rehash?(weaker)
    end
  end

  describe "upgrading a bcrypt user on login" do
    test "a correct login rewrites the stored hash to Argon2id" do
      email = "legacy-#{System.unique_integer([:positive])}@example.com"
      {:ok, user} = Accounts.register_user(%{email: email, password: @password})

      # Put the row back the way a pre-Argon2id database would hold it, on a
      # confirmed account: an unconfirmed one does not sign in by password.
      {:ok, user} =
        user
        |> Ecto.Changeset.change(
          hashed_password: Bcrypt.hash_pwd_salt(@password),
          confirmed_at: DateTime.utc_now(:second)
        )
        |> Repo.update()

      assert String.starts_with?(user.hashed_password, "$2")

      assert %Accounts.User{} = Accounts.get_user_by_email_and_password(email, @password)

      # The rewrite runs off the request, so wait for it rather than assuming.
      assert eventually(fn ->
               String.starts_with?(Repo.reload!(user).hashed_password, "$argon2id$")
             end)

      # …and the password still works afterwards, through the new hash.
      assert %Accounts.User{} = Accounts.get_user_by_email_and_password(email, @password)
      refute Accounts.get_user_by_email_and_password(email, "wrong")
    end

    test "a failed login leaves the bcrypt hash alone" do
      email = "legacy-#{System.unique_integer([:positive])}@example.com"
      {:ok, user} = Accounts.register_user(%{email: email, password: @password})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(hashed_password: Bcrypt.hash_pwd_salt(@password))
        |> Repo.update()

      refute Accounts.get_user_by_email_and_password(email, "wrong")
      Process.sleep(50)

      assert Repo.reload!(user).hashed_password == user.hashed_password
    end
  end

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end
end
