defmodule Gamend.SecretsTest do
  @moduledoc """
  The vault, and the two properties that make it worth having.

  Roundtripping a value is the easy half and would pass with no encryption at
  all. What matters is that a row which has been *moved* or *edited* in the
  database fails to open, because those are the cases where a quiet success
  means signing one studio's build with another studio's certificate.
  """
  use Gamend.DataCase, async: false

  import ExUnit.CaptureLog

  alias Gamend.Repo
  alias Gamend.Secrets
  alias Gamend.Secrets.Secret
  alias Gamend.SettingsHelpers

  @scope "forge_project"

  setup do
    original = SettingsHelpers.get(:gamend_core, Secrets, :keys)
    SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{key()}")

    on_exit(fn ->
      if original do
        SettingsHelpers.put(:gamend_core, Secrets, :keys, original)
      else
        SettingsHelpers.delete(:gamend_core, Secrets, :keys)
      end
    end)

    {:ok, project: Ecto.UUID.generate()}
  end

  defp key, do: :crypto.strong_rand_bytes(32) |> Base.encode64()

  describe "put/5 and fetch/3" do
    test "a value comes back out", %{project: project} do
      assert {:ok, _} = Secrets.put(@scope, project, "p12_password", "hunter2")
      assert {:ok, "hunter2"} = Secrets.fetch(@scope, project, "p12_password")
    end

    test "binary survives, not just text", %{project: project} do
      blob = :crypto.strong_rand_bytes(4096)

      assert {:ok, _} = Secrets.put(@scope, project, "certificate", blob)
      assert {:ok, ^blob} = Secrets.fetch(@scope, project, "certificate")
    end

    test "setting it again replaces it", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "api_key", "first")
      {:ok, _} = Secrets.put(@scope, project, "api_key", "second")

      assert {:ok, "second"} = Secrets.fetch(@scope, project, "api_key")
      assert [_one] = Secrets.list(@scope, project)
    end

    test "a secret nobody set is not found", %{project: project} do
      assert {:error, :not_found} = Secrets.fetch(@scope, project, "absent")
    end

    test "the plaintext is nowhere in the row", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "api_key", "correct-horse-battery")

      stored = Repo.get_by!(Secret, scope: @scope, scope_id: project, name: "api_key")

      refute stored.ciphertext == "correct-horse-battery"
      refute String.contains?(Base.encode64(stored.ciphertext), "correct-horse")
    end
  end

  describe "the owner is bound into the ciphertext" do
    # The case this exists for. Two studios, one certificate column: copying
    # the row must not hand the second studio the first one's certificate.
    test "a row moved to another owner will not open", %{project: project} do
      other = Ecto.UUID.generate()
      {:ok, _} = Secrets.put(@scope, project, "certificate", "the real one")

      Secret
      |> Repo.get_by!(scope: @scope, scope_id: project, name: "certificate")
      |> Ecto.Changeset.change(scope_id: other)
      |> Repo.update!()

      assert {:error, :undecryptable} = Secrets.fetch(@scope, other, "certificate")
    end

    test "a row renamed will not open", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "certificate", "the real one")

      Secret
      |> Repo.get_by!(scope: @scope, scope_id: project, name: "certificate")
      |> Ecto.Changeset.change(name: "other_certificate")
      |> Repo.update!()

      assert {:error, :undecryptable} = Secrets.fetch(@scope, project, "other_certificate")
    end

    test "a row moved to another scope will not open", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "certificate", "the real one")

      Secret
      |> Repo.get_by!(scope: @scope, scope_id: project, name: "certificate")
      |> Ecto.Changeset.change(scope: "something_else")
      |> Repo.update!()

      assert {:error, :undecryptable} = Secrets.fetch("something_else", project, "certificate")
    end
  end

  describe "tampering" do
    test "an edited ciphertext will not open", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "api_key", "original")

      stored = Repo.get_by!(Secret, scope: @scope, scope_id: project, name: "api_key")
      <<first, rest::binary>> = stored.ciphertext

      stored
      |> Ecto.Changeset.change(ciphertext: <<Bitwise.bxor(first, 1), rest::binary>>)
      |> Repo.update!()

      assert {:error, :undecryptable} = Secrets.fetch(@scope, project, "api_key")
    end

    test "an edited tag will not open", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "api_key", "original")

      stored = Repo.get_by!(Secret, scope: @scope, scope_id: project, name: "api_key")
      <<first, rest::binary>> = stored.tag

      stored
      |> Ecto.Changeset.change(tag: <<Bitwise.bxor(first, 1), rest::binary>>)
      |> Repo.update!()

      assert {:error, :undecryptable} = Secrets.fetch(@scope, project, "api_key")
    end

    test "every write gets its own IV", %{project: project} do
      {:ok, first} = Secrets.put(@scope, project, "a", "same value")
      {:ok, second} = Secrets.put(@scope, project, "b", "same value")

      refute first.iv == second.iv
      refute first.ciphertext == second.ciphertext
    end
  end

  describe "keys" do
    test "nothing works without one", %{project: project} do
      SettingsHelpers.delete(:gamend_core, Secrets, :keys)

      refute Secrets.configured?()
      assert {:error, :no_key} = Secrets.put(@scope, project, "api_key", "x")
    end

    @tag :capture_log
    test "a malformed key is no key", %{project: project} do
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:not-base64!!")

      refute Secrets.configured?()
      assert {:error, :no_key} = Secrets.put(@scope, project, "api_key", "x")
    end

    # Falling through to the next well-formed key would keep writing under the
    # one the operator just retired, and nothing would say so.
    @tag :capture_log
    test "a malformed current key does not fall through to an old one", %{project: project} do
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v2:not-base64!!,v1:#{key()}")

      refute Secrets.configured?()
      assert {:error, :no_key} = Secrets.put(@scope, project, "api_key", "x")
    end

    @tag :capture_log
    test "a malformed current key still lets old rows be read", %{project: project} do
      old = key()
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{old}")
      {:ok, _} = Secrets.put(@scope, project, "api_key", "x")

      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v2:not-base64!!,v1:#{old}")

      assert {:ok, "x"} = Secrets.fetch(@scope, project, "api_key")
    end

    test "a malformed key is reported by position, never by what it holds" do
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{key()},v0:not-base64!!")

      log = capture_log(fn -> assert Secrets.configured?() end)

      assert log =~ "entry 2"
      refute log =~ "not-base64"
    end

    @tag :capture_log
    test "a key of the wrong length is refused", %{project: project} do
      short = :crypto.strong_rand_bytes(16) |> Base.encode64()
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{short}")

      refute Secrets.configured?()
      assert {:error, :no_key} = Secrets.put(@scope, project, "api_key", "x")
    end

    # Removing a key before its rows have been rotated is how a certificate
    # becomes unreadable, so the failure has to be distinguishable from "there
    # is nothing here".
    test "a row whose key is gone is undecryptable, not missing", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "api_key", "x")
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v2:#{key()}")

      assert {:error, :undecryptable} = Secrets.fetch(@scope, project, "api_key")
    end
  end

  describe "rotation" do
    setup %{project: project} do
      old = key()
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{old}")
      {:ok, _} = Secrets.put(@scope, project, "api_key", "carried across")

      # The new key first, the old one still present: what an operator has
      # between adding a key and finishing the rotation.
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v2:#{key()},v1:#{old}")

      :ok
    end

    test "an old row still reads while both keys are configured", %{project: project} do
      assert {:ok, "carried across"} = Secrets.fetch(@scope, project, "api_key")
    end

    test "rotate/1 moves it to the current key", %{project: project} do
      assert Repo.get_by!(Secret, scope: @scope, scope_id: project, name: "api_key").key_id ==
               "v1"

      assert {:ok, %{moved: 1, stuck: 0}} = Secrets.rotate()

      assert Repo.get_by!(Secret, scope: @scope, scope_id: project, name: "api_key").key_id ==
               "v2"

      assert {:ok, "carried across"} = Secrets.fetch(@scope, project, "api_key")
    end

    test "a second pass has nothing left to do", %{project: _project} do
      {:ok, _} = Secrets.rotate()

      assert {:ok, %{moved: 0, stuck: 0}} = Secrets.rotate()
    end

    test "a pass covers every row, however small the batch", %{project: project} do
      both = SettingsHelpers.get(:gamend_core, Secrets, :keys)
      [_current, v1] = String.split(both, ",")

      SettingsHelpers.put(:gamend_core, Secrets, :keys, v1)
      for name <- ~w(a b c), do: {:ok, _} = Secrets.put(@scope, project, name, name)
      SettingsHelpers.put(:gamend_core, Secrets, :keys, both)

      assert {:ok, %{moved: 4, stuck: 0}} = Secrets.rotate(2)
      assert Enum.all?(Secrets.list(@scope, project), &(&1.key_id == "v2"))
    end
  end

  describe "a rotation past a row that will not open" do
    # Oldest first, so the row nothing can open is what a page would keep
    # coming back to.
    test "still reaches the rows behind it", %{project: project} do
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "gone:#{key()}")
      {:ok, _} = Secrets.put(@scope, project, "unreadable", "lost")

      old = key()
      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{old}")
      {:ok, _} = Secrets.put(@scope, project, "readable", "kept")

      SettingsHelpers.put(:gamend_core, Secrets, :keys, "v2:#{key()},v1:#{old}")

      assert {:ok, %{moved: 1, stuck: 1}} = Secrets.rotate(1)
      assert Secrets.get(@scope, project, "readable").key_id == "v2"
      assert {:ok, "kept"} = Secrets.fetch(@scope, project, "readable")
      assert Secrets.get(@scope, project, "unreadable").key_id == "gone"
    end
  end

  describe "listing and deleting" do
    test "list/2 is metadata, and is scoped to its owner", %{project: project} do
      other = Ecto.UUID.generate()
      {:ok, _} = Secrets.put(@scope, project, "a", "one", kind: "password")
      {:ok, _} = Secrets.put(@scope, other, "b", "two")

      assert [secret] = Secrets.list(@scope, project)
      assert secret.name == "a"
      assert secret.kind == "password"
      assert secret.byte_size == 3
    end

    test "delete/3 forgets one", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "a", "one")

      assert :ok = Secrets.delete(@scope, project, "a")
      assert {:error, :not_found} = Secrets.fetch(@scope, project, "a")
    end

    test "delete_all/2 forgets an owner's, and nobody else's", %{project: project} do
      other = Ecto.UUID.generate()
      {:ok, _} = Secrets.put(@scope, project, "a", "one")
      {:ok, _} = Secrets.put(@scope, project, "b", "two")
      {:ok, _} = Secrets.put(@scope, other, "a", "theirs")

      assert Secrets.delete_all(@scope, project) == 2
      assert Secrets.list(@scope, project) == []
      assert {:ok, "theirs"} = Secrets.fetch(@scope, other, "a")
    end
  end

  describe "use/3" do
    test "answers the value and records that it was used", %{project: project} do
      {:ok, _} = Secrets.put(@scope, project, "api_key", "x")
      assert is_nil(Secrets.get(@scope, project, "api_key").last_used_at)

      assert {:ok, "x"} = Secrets.use(@scope, project, "api_key")
      refute is_nil(Secrets.get(@scope, project, "api_key").last_used_at)
    end

    test "a missing secret is not recorded as used", %{project: project} do
      assert {:error, :not_found} = Secrets.use(@scope, project, "absent")
    end
  end

  describe "names" do
    test "are restricted, because they are half the authenticated data", %{project: project} do
      for bad <- ["Has Spaces", "UPPERCASE", "new\nline", "dash-es", "", "trailing "] do
        assert {:error, changeset} = Secrets.put(@scope, project, bad, "x")
        assert %{name: [_message]} = errors_on(changeset)
      end

      assert {:ok, _} = Secrets.put(@scope, project, "good_name_2", "x")
    end
  end

  describe "owners" do
    # `scope/scope_id/name` is what gets authenticated: a `/` in either of the
    # first two would let two different owners spell the same bytes.
    test "cannot hold the separator of the authenticated data", %{project: project} do
      assert {:error, changeset} = Secrets.put("forge/project", project, "api_key", "x")
      assert %{scope: [_message]} = errors_on(changeset)

      assert {:error, changeset} = Secrets.put(@scope, "a/b", "api_key", "x")
      assert %{scope_id: [_message]} = errors_on(changeset)
    end
  end

  describe "expired?/2" do
    test "a secret with no expiry never is" do
      refute Secret.expired?(%Secret{expires_at: nil})
    end

    test "one in the past has" do
      past = DateTime.add(DateTime.utc_now(), -1, :second)

      assert Secret.expired?(%Secret{expires_at: past})
    end

    test "one in the future has not" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      refute Secret.expired?(%Secret{expires_at: future})
    end
  end
end
