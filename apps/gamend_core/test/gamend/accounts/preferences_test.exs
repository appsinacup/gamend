defmodule Gamend.Accounts.PreferencesTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts.Preferences
  alias Gamend.AccountsFixtures

  defmodule Host do
    @moduledoc false
    def locales, do: ~w(en fr)
  end

  setup do
    Application.put_env(:gamend_core, :client_preferences, %{
      "game_sounds" => ~w(on off),
      "locale" => {Host, :locales}
    })

    on_exit(fn -> Application.delete_env(:gamend_core, :client_preferences) end)
    %{user: AccountsFixtures.user_fixture()}
  end

  test "a page sets the theme and the host's keys, each to a value allowed", %{user: user} do
    assert Preferences.client_keys() == %{
             "theme" => ~w(dark light system),
             "game_sounds" => ~w(on off),
             "locale" => ~w(en fr)
           }

    {:ok, user} = Preferences.put_client(user, "game_sounds", "off")
    {:ok, user} = Preferences.put_client(user, "locale", "fr")
    {:ok, user} = Preferences.put_client(user, "theme", "dark")
    assert Preferences.get(user) == %{"game_sounds" => "off", "locale" => "fr", "theme" => "dark"}

    assert {:error, :invalid} == Preferences.put_client(user, "locale", "xx")
    assert {:error, :invalid} == Preferences.put_client(user, "timezone", "Mars/Olympus")
    {:ok, user} = Preferences.put_client(user, "timezone", "Europe/Paris")
    assert Preferences.get(user)["timezone"] == "Europe/Paris"

    {:ok, user} = Preferences.put_client(user, "theme", "system")
    refute Map.has_key?(Preferences.get(user), "theme")
  end

  test "the row is what a page may set and the time zone, nil with no user", %{user: user} do
    {:ok, user} =
      Preferences.update(
        user,
        &Map.merge(&1, %{
          "timezone" => "UTC",
          "locale" => "fr",
          "notifications" => %{"off_all" => true}
        })
      )

    assert Preferences.row(%{user_id: user.id}) == %{"locale" => "fr", "timezone" => "UTC"}
    assert Preferences.row(%{user_id: nil}) == nil
    assert Preferences.row(%{user_id: Ecto.UUID.generate()}) == nil
  end
end
