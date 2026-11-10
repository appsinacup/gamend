defmodule GamendWeb.UserLive.SettingsAvatarTest do
  # async: false — this test swaps the global Storage.Local dir.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  alias Gamend.Accounts

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>

  setup do
    dir = Path.join(System.tmp_dir!(), "gs_settings_avatar_#{System.unique_integer([:positive])}")
    old = Application.get_env(:gamend_core, Gamend.Storage.Local)
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)

      if old,
        do: Application.put_env(:gamend_core, Gamend.Storage.Local, old),
        else: Application.delete_env(:gamend_core, Gamend.Storage.Local)
    end)

    :ok
  end

  defp pick_file(lv, name) do
    lv
    |> file_input("#avatar_form", :avatar, [%{name: name, content: @png, type: "image/png"}])
    |> render_upload(name)
  end

  defp save(lv), do: lv |> form("#avatar_form") |> render_submit()

  test "a picked file waits for Save, then stores and repoints profile_url", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")
    refute has_element?(lv, "#avatar_form[data-unsaved]")

    # The native file input clears its label on re-render, so the picked file
    # must be surfaced by us — otherwise it looks like nothing was selected.
    assert pick_file(lv, "me.png") =~ "me.png"

    assert Accounts.get_user(user.id).profile_url in [nil, ""]
    assert Gamend.Storage.list_objects(prefix: "avatars/#{user.id}/") == []
    assert has_element?(lv, "#avatar_form[data-unsaved]")

    save(lv)

    assert Accounts.get_user(user.id).profile_url =~ "avatars/#{user.id}"
    refute has_element?(lv, "#avatar_form[data-unsaved]")
  end

  test "a file dropped before Save changes nothing", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    pick_file(lv, "me.png")
    lv |> element("#avatar_form button[phx-click=cancel_avatar]") |> render_click()

    refute has_element?(lv, "#avatar_form[data-unsaved]")
    assert Accounts.get_user(user.id).profile_url in [nil, ""]
  end

  test "saving a new avatar prunes the previous object", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    pick_file(lv, "first.png")
    save(lv)
    first_url = Accounts.get_user(user.id).profile_url
    assert length(Gamend.Storage.list_objects(prefix: "avatars/#{user.id}/")) == 1

    pick_file(lv, "second.png")
    save(lv)
    second_url = Accounts.get_user(user.id).profile_url

    # The new avatar replaces the old — exactly one object remains, and it is
    # the one profile_url now points at.
    objects = Gamend.Storage.list_objects(prefix: "avatars/#{user.id}/")
    assert length(objects) == 1
    refute first_url == second_url
    assert second_url =~ "avatars/#{user.id}"
  end

  test "one of the site's icons waits for Save, then is the avatar and replaces the picture", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    pick_file(lv, "me.png")
    save(lv)
    uploaded = Accounts.get_user(user.id).profile_url
    assert uploaded =~ "avatars/#{user.id}"

    lv
    |> form("#avatar_form", avatar_icon: %{profile_url: "/icons/rocket-launch.svg"})
    |> render_change()

    assert Accounts.get_user(user.id).profile_url == uploaded
    assert has_element?(lv, "#avatar_form[data-unsaved]")

    assert has_element?(
             lv,
             ~s(#avatar_form input[value="/icons/rocket-launch.svg"][checked])
           )

    save(lv)

    # In the colour already chosen for it, with no click on a colour.
    picked = Accounts.get_user(user.id).profile_url
    assert picked =~ ~r{\A/icons/rocket-launch\.svg\?color=[a-z]+\z}
    refute has_element?(lv, "#avatar_form[data-unsaved]")

    # The picture it replaced is gone from storage.
    assert Gamend.Storage.list_objects(prefix: "avatars/#{user.id}/") == []

    # A forged pick of anything but one of the site's icons changes nothing.
    render_submit(lv, "save_avatar", %{
      "avatar_icon" => %{"profile_url" => "/icons/not-ours.svg"}
    })

    assert Accounts.get_user(user.id).profile_url == picked
  end

  test "an icon clicked with a file picked drops the file", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    pick_file(lv, "me.png")

    lv
    |> element(~s(#avatar_form input[value="/icons/rocket-launch.svg"]))
    |> render_click()

    refute render(lv) =~ "me.png"
  end

  test "the icon picked in a colour is the avatar in it; with none picked, the id's is lit", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    # Never picked: the icon their id gives them is the one lit, and nothing
    # is unsaved for it.
    own = Gamend.Icons.for_id(user.id)
    own_name = Gamend.Icons.name(own)
    assert has_element?(lv, ~s(#avatar_form input[value="/icons/#{own_name}.svg"][checked]))
    refute has_element?(lv, "#avatar_form[data-unsaved]")

    lv
    |> form("#avatar_form",
      avatar_icon: %{profile_url: "/icons/rocket-launch.svg", profile_url_color: "error"}
    )
    |> render_submit()

    assert Accounts.get_user(user.id).profile_url == "/icons/rocket-launch.svg?color=error"
    assert has_element?(lv, ~s(#avatar_form input[value="error"][checked]))

    lv
    |> form("#avatar_form", avatar_icon: %{profile_url_color: ""})
    |> render_submit()

    assert Accounts.get_user(user.id).profile_url == "/icons/rocket-launch.svg"
  end

  test "a name typed is unsaved until it is saved", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> form("#display_form", user: %{display_name: "Someone New"}) |> render_change()
    assert has_element?(lv, "#display_form[data-unsaved]")

    lv |> form("#display_form", user: %{display_name: "Someone New"}) |> render_submit()
    refute has_element?(lv, "#display_form[data-unsaved]")
  end
end
