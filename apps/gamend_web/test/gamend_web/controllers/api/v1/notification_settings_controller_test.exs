defmodule GamendWeb.Api.V1.NotificationSettingsControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.TimeZone
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications.Preferences
  alias GamendWeb.Auth.Guardian

  @streak %{
    key: "streak",
    label: "Streak about to end",
    defaults: %{"in_app" => true, "email" => false, "push" => false},
    configurable: ["email", "push"]
  }

  setup do
    old = Application.get_env(:gamend_core, :notification_groups)
    Application.put_env(:gamend_core, :notification_groups, [@streak])

    on_exit(fn ->
      if old,
        do: Application.put_env(:gamend_core, :notification_groups, old),
        else: Application.delete_env(:gamend_core, :notification_groups)
    end)

    :ok
  end

  defp auth_conn(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp group(settings, key), do: Enum.find(settings["groups"], &(&1["key"] == key))

  test "GET answers the tab's rows, the switches and the time zone", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    settings =
      conn
      |> auth_conn(user)
      |> get("/api/v1/me/notification_settings")
      |> json_response(200)
      |> Map.fetch!("data")

    assert settings["channels"] == Preferences.channels()

    assert group(settings, "streak") == %{
             "key" => "streak",
             "label" => "Streak about to end",
             "enabled" => %{"in_app" => true, "email" => false, "push" => false},
             "configurable" => ["email", "push"]
           }

    assert group(settings, "account")["configurable"] == []
    refute group(settings, "moderation")

    assert %{
             "off_all" => false,
             "off_email" => false,
             "off_push" => false,
             "timezone" => "",
             "timezone_manual" => false
           } = settings
  end

  test "PUT changes what it is sent and keeps the rest", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    settings =
      conn
      |> auth_conn(user)
      |> put("/api/v1/me/notification_settings", %{
        groups: %{"streak" => %{"push" => true}},
        off_email: true,
        timezone: "Europe/Bucharest"
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert group(settings, "streak")["enabled"]["push"] == true
    assert %{"off_email" => true, "off_all" => false} = settings
    assert %{"timezone" => "Europe/Bucharest", "timezone_manual" => true} = settings

    user = Accounts.get_user(user.id)
    assert Preferences.enabled?(user, "streak", "push")
    assert Preferences.off?(user, "off_email")
    assert TimeZone.manual?(user)

    settings =
      conn
      |> auth_conn(user)
      |> put("/api/v1/me/notification_settings", %{off_email: false, timezone: ""})
      |> json_response(200)
      |> Map.fetch!("data")

    assert group(settings, "streak")["enabled"]["push"] == true
    assert %{"off_email" => false, "timezone_manual" => false} = settings
  end

  test "PUT refuses a change whole, with nothing written", %{conn: conn} do
    # The first account made can be the site's admin, whose own groups are
    # open to them.
    _first = AccountsFixtures.user_fixture()
    user = AccountsFixtures.user_fixture()
    refute user.is_admin

    for {body, status, code} <- [
          {%{groups: %{"nope" => %{"push" => true}}, off_all: true}, 404, "unknown_group"},
          {%{groups: %{"moderation" => %{"push" => false}}}, 404, "unknown_group"},
          {%{groups: %{"streak" => %{"in_app" => false}}, off_all: true}, 403,
           "not_configurable"},
          {%{off_all: true, timezone: "Mars/Olympus"}, 422, "invalid_time_zone"}
        ] do
      assert %{"error" => ^code} =
               conn
               |> auth_conn(user)
               |> put("/api/v1/me/notification_settings", body)
               |> json_response(status)
    end

    assert Accounts.Preferences.get(Accounts.get_user(user.id)) == %{}
  end

  test "needs a signed-in user", %{conn: conn} do
    assert conn |> get("/api/v1/me/notification_settings") |> response(401)
    assert conn |> put("/api/v1/me/notification_settings", %{off_all: true}) |> response(401)
  end
end
