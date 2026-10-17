defmodule GamendWeb.PreferenceControllerTest do
  @moduledoc """
  `PUT /preferences`: a preference the page sets, saved to the account — the
  theme, and the keys a host allows (`:client_preferences`) — and the theme
  rendered from it (`GamendWeb.Plugs.ColorMode`).
  """
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.Preferences

  setup do
    previous = Application.get_env(:gamend_core, :client_preferences)
    Application.put_env(:gamend_core, :client_preferences, %{"game_sounds" => ~w(on off)})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :client_preferences, previous),
        else: Application.delete_env(:gamend_core, :client_preferences)
    end)
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the theme and a host's key are saved; anything else is refused", %{
      conn: conn,
      user: user
    } do
      assert conn |> put("/preferences", %{key: "theme", value: "dark"}) |> response(204)
      assert conn |> put("/preferences", %{key: "game_sounds", value: "off"}) |> response(204)
      assert conn |> put("/preferences", %{key: "theme", value: "pink"}) |> response(422)
      assert conn |> put("/preferences", %{key: "timezone", value: "UTC"}) |> response(422)

      prefs = Preferences.get(Accounts.get_user!(user.id))
      assert prefs["theme"] == "dark"
      assert prefs["game_sounds"] == "off"
      refute Map.has_key?(prefs, "timezone")

      # "system" forgets the saved theme: the device decides again.
      assert conn |> put("/preferences", %{key: "theme", value: "system"}) |> response(204)
      refute Map.has_key?(Preferences.get(Accounts.get_user!(user.id)), "theme")
    end

    test "the saved theme is rendered, over the browser's cookie", %{conn: conn, user: user} do
      {:ok, _} = Preferences.put_client(user, "theme", "dark")

      html =
        conn
        |> put_req_cookie("phx_theme", "light")
        |> get("/")
        |> html_response(200)

      assert html =~ ~s(data-theme="dark")
      assert html =~ ~s(data-theme-saved="dark")
    end
  end

  test "a visitor has nothing to save to: 204, and nothing rendered as saved", %{conn: conn} do
    assert conn |> put("/preferences", %{key: "theme", value: "dark"}) |> response(204)
    assert conn |> put("/preferences", %{key: "theme", value: "pink"}) |> response(422)

    html = conn |> put_req_cookie("phx_theme", "dark") |> get("/") |> html_response(200)
    assert html =~ ~s(data-theme="dark")
    refute html =~ "data-theme-saved"
  end
end
