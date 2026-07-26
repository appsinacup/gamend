defmodule GameServerWeb.UserLive.SettingsAvatarTest do
  # async: false — this test swaps the global Storage.Local dir.
  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GameServer.AccountsFixtures

  alias GameServer.Accounts

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>

  setup do
    dir = Path.join(System.tmp_dir!(), "gs_settings_avatar_#{System.unique_integer([:positive])}")
    old = Application.get_env(:game_server_core, GameServer.Storage.Local)
    Application.put_env(:game_server_core, GameServer.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)

      if old,
        do: Application.put_env(:game_server_core, GameServer.Storage.Local, old),
        else: Application.delete_env(:game_server_core, GameServer.Storage.Local)
    end)

    :ok
  end

  test "uploading an avatar stores it and repoints profile_url", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    avatar =
      file_input(lv, "#avatar_form", :avatar, [
        %{name: "me.png", content: @png, type: "image/png"}
      ])

    # The native file input clears its label on re-render, so the picked file
    # must be surfaced by us — otherwise it looks like nothing was selected.
    assert render_upload(avatar, "me.png") =~ "me.png"

    # This is the event that previously crashed with a KeyError — assert it
    # completes and repoints the avatar into our storage.
    lv |> element("#avatar_form") |> render_submit()

    updated = Accounts.get_user(user.id)
    assert updated.profile_url =~ "avatars/#{user.id}"
  end

  test "uploading a new avatar prunes the previous object", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    submit_avatar = fn name ->
      lv
      |> file_input("#avatar_form", :avatar, [%{name: name, content: @png, type: "image/png"}])
      |> render_upload(name)

      lv |> element("#avatar_form") |> render_submit()
    end

    submit_avatar.("first.png")
    first_url = Accounts.get_user(user.id).profile_url
    assert length(GameServer.Storage.list_objects(prefix: "avatars/#{user.id}/")) == 1

    submit_avatar.("second.png")
    second_url = Accounts.get_user(user.id).profile_url

    # The new avatar replaces the old — exactly one object remains, and it is
    # the one profile_url now points at.
    objects = GameServer.Storage.list_objects(prefix: "avatars/#{user.id}/")
    assert length(objects) == 1
    refute first_url == second_url
    assert second_url =~ "avatars/#{user.id}"
  end
end
