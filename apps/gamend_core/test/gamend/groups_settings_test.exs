defmodule Gamend.GroupsSettingsTest do
  # The host's groups settings (`Gamend.Groups`): the types a group may be
  # (`types`, the first the default), whom an admin may invite (`invites`),
  # every group's member cap (`max_members`) and whether a title is unique
  # (`unique_titles`). Forge and Gamend Cloud allow `hidden` alone, invite
  # `anyone`, hold 100 and let titles repeat: teams of colleagues, never
  # public, and a taken title would tell of a hidden group.
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Groups

  setup do
    previous = Application.get_env(:gamend_core, Groups, [])
    on_exit(fn -> Application.put_env(:gamend_core, Groups, previous) end)

    %{owner: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  defp put_settings(settings) do
    Application.put_env(
      :gamend_core,
      Groups,
      Keyword.merge(Application.get_env(:gamend_core, Groups, []), settings)
    )
  end

  defp title, do: "crew-#{System.unique_integer([:positive])}"

  test "by default every type is allowed, and a group is public" do
    assert Groups.types() == ["public", "private", "hidden"]
    refute Groups.invite_anyone?()
  end

  test "a group with no type is the host's first; one it does not allow is refused", %{
    owner: owner
  } do
    put_settings(types: ["hidden"])

    assert {:ok, %{type: "hidden"} = group} = Groups.create_group(owner.id, %{"title" => title()})

    assert {:error, changeset} =
             Groups.create_group(owner.id, %{"title" => title(), "type" => "public"})

    assert %{type: [_]} = errors_on(changeset)

    assert {:error, changeset} = Groups.update_group(owner.id, group.id, %{"type" => "public"})
    assert %{type: [_]} = errors_on(changeset)
  end

  test "a group made before keeps its type when edited", %{owner: owner} do
    {:ok, group} = Groups.create_group(owner.id, %{"title" => title(), "type" => "public"})
    put_settings(types: ["hidden"])

    assert {:ok, %{type: "public", description: "still"}} =
             Groups.update_group(owner.id, group.id, %{"description" => "still"})
  end

  test "names that are not types are dropped, and none at all leaves every type" do
    put_settings(types: ["team", "private"])
    assert Groups.types() == ["private"]

    put_settings(types: ["team"])
    assert Groups.types() == ["public", "private", "hidden"]
  end

  test "an admin invites a stranger only where anyone may be invited", %{
    owner: owner,
    other: other
  } do
    {:ok, group} = Groups.create_group(owner.id, %{"title" => title()})
    assert {:error, :not_connected} = Groups.invite_to_group(owner.id, group.id, other.id)

    put_settings(invites: :anyone)
    assert Groups.invite_anyone?()
    assert {:ok, _invite} = Groups.invite_to_group(owner.id, group.id, other.id)
  end

  test "a fixed member cap is every new group's, whatever it is asked", %{owner: owner} do
    assert Groups.fixed_max_members() == nil
    put_settings(max_members: 100)
    assert Groups.fixed_max_members() == 100

    assert {:ok, %{max_members: 100} = group} =
             Groups.create_group(owner.id, %{"title" => title(), "max_members" => 7})

    assert {:ok, %{max_members: 100}} =
             Groups.update_group(owner.id, group.id, %{max_members: 3, description: "x"})
  end

  test "with unique titles off two groups share a title; their slugs differ", %{
    owner: owner,
    other: other
  } do
    {:ok, _} = Groups.create_group(owner.id, %{"title" => "Team"})
    assert {:error, changeset} = Groups.create_group(other.id, %{"title" => "Team"})
    assert %{title: ["has already been taken"]} = errors_on(changeset)

    put_settings(unique_titles: false)
    refute Groups.unique_titles?()

    assert {:ok, %{slug: "team"} = theirs} = Groups.create_group(other.id, %{"title" => "Team"})
    assert {:ok, %{slug: "team-2"}} = Groups.create_group(owner.id, %{"title" => "Team"})

    assert {:ok, %{title: "Team"}} =
             Groups.update_group(other.id, theirs.id, %{"description" => "still"})

    assert %{title: "Team"} = Groups.get_group_by_title("Team")
  end
end
