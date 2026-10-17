defmodule GamendWeb.AdminCard do
  @moduledoc """
  Host-supplied cards for the admin dashboard (`/admin`).

  Core draws a card for each of its own admin pages. A host's admin pages
  (its traffic, its tools) are the host's to describe, so it lists modules
  that answer `cards/0`, and the dashboard draws their cards after core's:

      # config/config.exs
      config :gamend_web, :admin_cards, [GamendHost.AdminCards]

      defmodule GamendHost.AdminCards do
        @behaviour GamendWeb.AdminCard

        @impl true
        def cards do
          [
            %{
              title: "Traffic",
              path: "/admin/traffic",
              value: 120,
              lines: ["Visits today", {"Humans", 80}, {"Docs", nil, "/admin/docs"}]
            }
          ]
        end
      end

  A card is a `title`, the `path` its "View" link opens, an optional headline
  `value`, and `lines`: a string for a plain line, `{label, value}` for a
  figure, `{label, value, path}` for a figure or a bare label (`value` nil)
  that links somewhere.

  `cards/0` runs on every dashboard mount, beside core's own queries, so keep
  it to counts. A raise is logged and the module's cards are left out; the
  dashboard still renders.
  """

  @type line :: String.t() | {String.t(), term()} | {String.t(), term(), String.t()}
  @type card :: %{
          required(:title) => String.t(),
          required(:path) => String.t(),
          optional(:value) => term(),
          optional(:lines) => [line()]
        }

  @doc "The cards this module adds to `/admin`, in order."
  @callback cards() :: [card()]

  require Logger

  @doc "Every configured module's cards (`config :gamend_web, :admin_cards`)."
  @spec all() :: [card()]
  def all do
    :gamend_web
    |> Application.get_env(:admin_cards, [])
    |> Enum.flat_map(&cards_of/1)
  end

  defp cards_of(module) do
    module.cards()
  rescue
    error ->
      Logger.warning("admin cards from #{inspect(module)} failed: " <> Exception.message(error))

      []
  end
end
