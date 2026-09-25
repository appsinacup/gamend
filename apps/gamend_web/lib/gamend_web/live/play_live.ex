defmodule GamendWeb.PlayLive do
  @moduledoc """
  LiveView wrapper that embeds the Godot web export (`/game/index.html`)
  inside the app layout so the navbar is visible.

  The game itself runs in an iframe with its own COOP/COEP headers
  (set by `GamendWeb.Plugs.GameHeaders`) so `SharedArrayBuffer` works.

  When the user is session-authenticated, this LiveView mints a short-lived
  JWT access-token (and a refresh-token) so the Godot game can call the API.
  They are handed over through **localStorage only**: the `GameAuth` hook writes
  `gamend_access_token` / `gamend_refresh_token`, and the game reads them with
  `JavaScriptBridge.eval("localStorage.getItem('gamend_refresh_token')")`.

  The iframe `src` is a CONSTANT and must stay one. `mount/2` runs at least
  twice per page (dead render, then connected mount, then again on every socket
  reconnect) and mints fresh tokens each time. When those tokens were part of
  the `src` fragment, every mount produced a different URL, the browser reloaded
  the iframe, and a second Godot/WASM instance booted before the first was
  collected — roughly doubling the heap and getting the tab killed on iOS.
  `phx-update="ignore"` does not save us here; the only safe answer is a `src`
  that cannot change.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.Plugs.FeatureGate

  @impl true
  def mount(_params, _session, socket) do
    unless FeatureGate.enabled?(:play) do
      raise GamendWeb.NotFoundError
    end

    {:ok, assign(socket, token_data: build_token_data(Scope.user(socket.assigns.current_scope)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      flush
    >
      <div
        id="game-container"
        phx-hook="GameViewport"
        class="relative w-full h-full overflow-hidden"
        style="touch-action: manipulation;"
      >
        <div
          id="game-auth"
          phx-hook="GameAuth"
          phx-update="ignore"
          data-access-token={@token_data[:access_token] || ""}
          data-refresh-token={@token_data[:refresh_token] || ""}
        >
        </div>

        <%!-- src is a literal on purpose: any change reloads the iframe and
              boots a second WASM instance. See the moduledoc. --%>
        <iframe
          id="game-frame"
          title={gettext("Game")}
          src="/game/index.html"
          class="w-full h-full border-0"
          allow="autoplay; fullscreen"
          allowfullscreen
          phx-update="ignore"
        ></iframe>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_token_data(nil), do: %{}

  defp build_token_data(user) do
    with {:ok, access_token, _claims} <-
           Guardian.encode_and_sign(user, %{}, token_type: "access"),
         {:ok, refresh_token, _claims} <-
           Guardian.encode_and_sign(user, %{}, token_type: "refresh") do
      %{access_token: access_token, refresh_token: refresh_token}
    else
      _error -> %{}
    end
  end
end
