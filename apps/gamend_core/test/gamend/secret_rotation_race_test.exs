defmodule Gamend.SecretRotationRaceTest do
  @moduledoc """
  A key rotation walking the table while owners write and delete their
  secrets.

  The walk read a row, decrypted it and upserted the old value by name, so a
  `put/5` that landed between the two was overwritten with the value before
  it, a deleted secret came back, and the walk's `{:ok, _} =` raised on a
  conflict. It now re-encrypts only the row it read (`Repo.compare_and_set/2`
  on id, key and last write) and skips one that changed.
  """

  use Gamend.RaceCase

  alias Gamend.Secrets
  alias Gamend.Secrets.Secret
  alias Gamend.SettingsHelpers

  @scope "rotation_race"
  @rows 12

  setup do
    original = SettingsHelpers.get(:gamend_core, Secrets, :keys)
    old = key()
    SettingsHelpers.put(:gamend_core, Secrets, :keys, "v1:#{old}")
    project = Ecto.UUID.generate()

    unboxed(fn ->
      for i <- 1..@rows, do: {:ok, _} = Secrets.put(@scope, project, "s#{i}", "old #{i}")
    end)

    SettingsHelpers.put(:gamend_core, Secrets, :keys, "v2:#{key()},v1:#{old}")

    cleanup(fn -> Repo.delete_all(from s in Secret, where: s.scope_id == ^project) end)

    on_exit(fn ->
      if original,
        do: SettingsHelpers.put(:gamend_core, Secrets, :keys, original),
        else: SettingsHelpers.delete(:gamend_core, Secrets, :keys)
    end)

    %{project: project}
  end

  test "a rotation never writes back an old value or a deleted secret", %{project: project} do
    writes =
      for i <- 1..@rows do
        if rem(i, 3) == 0,
          do: fn -> Secrets.delete(@scope, project, "s#{i}") end,
          else: fn -> Secrets.put(@scope, project, "s#{i}", "new #{i}") end
      end

    [rotated | written] = race([fn -> Secrets.rotate(5) end | writes])

    refute Enum.any?([rotated | written], &match?({:raised, _}, &1)), inspect(rotated)
    assert {:ok, %{stuck: 0}} = rotated

    unboxed(fn ->
      for i <- 1..@rows do
        if rem(i, 3) == 0 do
          assert Secrets.fetch(@scope, project, "s#{i}") == {:error, :not_found}
        else
          assert Secrets.fetch(@scope, project, "s#{i}") == {:ok, "new #{i}"}
        end
      end

      assert Enum.all?(Secrets.list(@scope, project), &(&1.key_id == "v2"))
    end)
  end

  defp key, do: :crypto.strong_rand_bytes(32) |> Base.encode64()
end
