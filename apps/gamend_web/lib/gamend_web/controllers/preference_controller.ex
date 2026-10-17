defmodule GamendWeb.PreferenceController do
  @moduledoc """
  `PUT /preferences` (`key`, `value`): a preference the page itself sets,
  saved to the signed-in account (`Gamend.Accounts.Preferences.put_client/3`)
  — the theme, and what the host allows. A visitor has no account to save to,
  so their page keeps its own copy and this answers 204 all the same. 422 for
  a key or value that is not allowed.
  """
  use GamendWeb, :controller

  alias Gamend.Accounts.Preferences
  alias Gamend.Accounts.Scope

  def update(conn, %{"key" => key, "value" => value}) when is_binary(key) and is_binary(value) do
    case Scope.user(conn.assigns[:current_scope]) do
      nil ->
        if value in Map.get(Preferences.client_keys(), key, []),
          do: send_resp(conn, 204, ""),
          else: send_resp(conn, 422, "")

      user ->
        case Preferences.put_client(user, key, value) do
          {:ok, _user} -> send_resp(conn, 204, "")
          {:error, _reason} -> send_resp(conn, 422, "")
        end
    end
  end

  def update(conn, _params), do: send_resp(conn, 422, "")
end
