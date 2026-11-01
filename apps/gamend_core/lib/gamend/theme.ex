defmodule Gamend.Theme do
  @moduledoc """
  Behaviour for pluggable site theming providers.

  Implementations should provide a map-like theme object that the UI
  and templates can render from. We ship a small JSON-backed default
  implementation that reads a JSON file (see Gamend.Theme.JSONConfig).

  Recommended keys in the theme map:
    - "title" (string)
    - "tagline" (string)
    - "description" (string)
    - "contact_email" (string) — shown with a mailto link on /privacy,
      /data_deletion and /terms; without it they say "support channels"
    - "theme_color" (string or map with light/dark keys)
    - "brand_color" (`#rrggbb`) — the buttons on Stripe's checkout page,
      which also takes "title" and an https png/jpg/gif "logo"
    - "navigation" (map of nav link arrays)
    - "useful_links" (list)
    - "features" (list)
    - "metadata" (map)
  """

  @callback get_theme() :: map()
  @callback get_setting(key :: atom() | String.t()) :: any()
  @callback reload() :: :ok | {:error, term()}
end
