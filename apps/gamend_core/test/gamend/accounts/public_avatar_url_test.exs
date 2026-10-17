defmodule Gamend.Accounts.PublicAvatarUrlTest do
  @moduledoc """
  A sign-in stores the provider's avatar URL until `AvatarMirror` copies it to
  our storage. Shown, that URL sends every viewer's IP to the provider, and a
  Discord one carries the player's Discord id. So only an avatar under the
  user's own `avatars/<id>/` key ever leaves the server.
  """
  use ExUnit.Case, async: true

  alias Gamend.Accounts.Broadcasts
  alias Gamend.Accounts.User

  @id "0190c0de-0000-7000-8000-000000000001"
  @hosted "/storage/avatars/#{@id}/abc.png"
  @provider_urls [
    "https://cdn.discordapp.com/avatars/123456789012345678/abc.png",
    "https://lh3.googleusercontent.com/a/abc=s96-c",
    "https://avatars.githubusercontent.com/u/583231",
    "https://steamcommunity.com/profiles/76561197960287930/",
    # Another user's stored avatar.
    "/storage/avatars/0190c0de-0000-7000-8000-000000000002/abc.png"
  ]

  test "an avatar we host is public" do
    assert User.public_avatar_url(%User{id: @id, profile_url: @hosted}) == @hosted

    cdn = "https://cdn.example.com/avatars/#{@id}/abc.png"
    assert User.public_avatar_url(%User{id: @id, profile_url: cdn}) == cdn
  end

  test "a provider's URL is not" do
    for url <- @provider_urls do
      assert User.public_avatar_url(%User{id: @id, profile_url: url}) == nil, url
    end
  end

  test "no avatar, no user" do
    assert User.public_avatar_url(%User{id: @id, profile_url: nil}) == nil
    assert User.public_avatar_url(%User{id: @id, profile_url: ""}) == nil
    assert User.public_avatar_url(%User{id: nil, profile_url: @hosted}) == nil
    assert User.public_avatar_url(nil) == nil
  end

  test "every user payload sends it empty" do
    for url <- @provider_urls do
      user = %User{id: @id, profile_url: url}

      assert User.serialize_brief(user).profile_url == ""
      assert Broadcasts.serialize_user_payload(user).profile_url == ""
      assert user |> Jason.encode!() |> Jason.decode!() |> Map.fetch!("profile_url") == ""
    end

    user = %User{id: @id, profile_url: @hosted}
    assert User.serialize_brief(user).profile_url == @hosted
    assert Broadcasts.serialize_user_payload(user).profile_url == @hosted
    assert user |> Jason.encode!() |> Jason.decode!() |> Map.fetch!("profile_url") == @hosted
  end
end
