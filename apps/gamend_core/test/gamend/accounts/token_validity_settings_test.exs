defmodule Gamend.Accounts.TokenValiditySettingsTest do
  # Settings are global Application config.
  use ExUnit.Case, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.UserToken
  alias Gamend.SettingsHelpers

  @keys [:session_days, :magic_link_minutes, :confirm_email_days, :change_email_days]

  setup do
    on_exit(fn -> for key <- @keys, do: SettingsHelpers.delete(:gamend_core, Accounts, key) end)
  end

  test "the defaults are the windows the tokens always had" do
    assert UserToken.session_validity_in_days() == 14
    assert UserToken.magic_link_validity_in_minutes() == 15
    assert UserToken.confirm_validity_in_days() == 7
    assert UserToken.change_email_validity_in_days() == 7
  end

  test "each window follows its setting" do
    SettingsHelpers.put(:gamend_core, Accounts, :session_days, 30)
    SettingsHelpers.put(:gamend_core, Accounts, :magic_link_minutes, 30)
    SettingsHelpers.put(:gamend_core, Accounts, :confirm_email_days, 2)
    SettingsHelpers.put(:gamend_core, Accounts, :change_email_days, 1)

    assert UserToken.session_validity_in_days() == 30
    assert UserToken.magic_link_validity_in_minutes() == 30
    assert UserToken.confirm_validity_in_days() == 2
    assert UserToken.change_email_validity_in_days() == 1
  end

  test "a magic link lasts an hour at most, and every window at least one unit" do
    SettingsHelpers.put(:gamend_core, Accounts, :magic_link_minutes, 24 * 60)
    assert UserToken.magic_link_validity_in_minutes() == 60

    SettingsHelpers.put(:gamend_core, Accounts, :session_days, 0)
    assert UserToken.session_validity_in_days() == 1
  end

  test "the sudo window follows its setting, and submitting gets ten minutes more" do
    SettingsHelpers.put(:gamend_core, Accounts, :sudo_mode_minutes, 5)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, :sudo_mode_minutes) end)

    user = %Accounts.User{authenticated_at: DateTime.add(DateTime.utc_now(), -12, :minute)}

    assert Accounts.sudo_mode_minutes() == 5
    refute Accounts.sudo_mode?(user, -Accounts.sudo_mode_minutes())
    assert Accounts.sudo_mode?(user)
  end
end
