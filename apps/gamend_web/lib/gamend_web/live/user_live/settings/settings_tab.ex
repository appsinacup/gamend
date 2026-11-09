defmodule GamendWeb.UserLive.Settings.SettingsTab do
  @moduledoc """
  The tabs of the account settings page.
  """

  use Gamend.Names,
      ~w(account groups data wallet api_tokens friends devices items notifications payments)
end
