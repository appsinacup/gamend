defmodule GamendWeb.SettingsTab do
  @moduledoc """
  The tabs of the account settings page.
  """

  @all ~w(account groups data wallet api_tokens)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
