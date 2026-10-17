defmodule GamendWeb.Plugs.ColorMode do
  @moduledoc """
  Assigns `:color_mode` so that the root layout can render the `data-theme`
  attribute server-side, preventing a Flash of Unstyled Content (FOUC) when
  the reader has chosen dark mode.

  A signed-in reader's saved theme (`Gamend.Accounts.Preferences.theme/1`)
  wins, and is also assigned as `:theme_saved`, which the layout hands to
  `theme-init.js` so the browser's copy follows the account. Otherwise the
  `phx_theme` cookie the client-side switcher sets. Runs after the scope is
  fetched. Only `"dark"` or `"light"` — any other value is ignored.
  """

  import Plug.Conn

  alias Gamend.Accounts.Preferences
  alias Gamend.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    case Preferences.theme(Scope.user(conn.assigns[:current_scope])) do
      nil ->
        case conn.cookies["phx_theme"] do
          theme when theme in ["dark", "light"] -> assign(conn, :color_mode, theme)
          _ -> conn
        end

      saved ->
        conn |> assign(:color_mode, saved) |> assign(:theme_saved, saved)
    end
  end
end
