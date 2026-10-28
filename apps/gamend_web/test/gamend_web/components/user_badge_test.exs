defmodule GamendWeb.Components.UserBadgeTest do
  @moduledoc """
  `user_badge/1` is the host's short tag beside a player's name ("Pro"), drawn
  by `player_card/1` wherever a player is named. Unset, blank or no account
  renders nothing, so a card never carries an empty badge.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GamendWeb.CoreComponents

  defmodule Badges do
    def badge(%{metadata: %{"pro" => true}}), do: "Pro"
    def badge(%{metadata: %{"pro" => "blank"}}), do: ""
    def badge(_user), do: nil
  end

  setup do
    original = Application.get_env(:gamend_web, :user_badge)
    Application.put_env(:gamend_web, :user_badge, {Badges, :badge})

    on_exit(fn ->
      if original,
        do: Application.put_env(:gamend_web, :user_badge, original),
        else: Application.delete_env(:gamend_web, :user_badge)
    end)

    :ok
  end

  test "the host's badge, beside the name on a player card" do
    user = %Gamend.Accounts.User{id: Ecto.UUID.generate(), metadata: %{"pro" => true}}

    assert CoreComponents.user_badge_text(user) == "Pro"

    html = render_component(&CoreComponents.player_card/1, name: "Ana", user: user)
    assert html =~ ~r{Ana</span>\s*<span class="badge[^"]*">Pro</span>}
  end

  test "nothing for a blank answer, nil, no account or no config" do
    assert CoreComponents.user_badge_text(%{metadata: %{"pro" => "blank"}}) == nil
    assert CoreComponents.user_badge_text(%{metadata: %{}}) == nil
    assert CoreComponents.user_badge_text(nil) == nil

    Application.delete_env(:gamend_web, :user_badge)
    assert CoreComponents.user_badge_text(%{metadata: %{"pro" => true}}) == nil

    html = render_component(&CoreComponents.player_card/1, name: "Ana", user: nil)
    refute html =~ "badge-warning"
  end
end
