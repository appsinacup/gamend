defmodule GamendWeb.AdminCard do
  @moduledoc """
  A host's entries on the admin dashboard (`/admin`).

  Core draws a card for each of its own admin pages. A host's admin pages (its
  traffic, its tools) are the host's to describe, so it lists modules that
  answer `cards/0`, and the dashboard draws them in a section of their own,
  after core's:

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
              icon: "hero-chart-bar-solid",
              color: "cyan",
              value: 120,
              lines: ["Visits today", {"Humans", 80}, {"Docs", nil, "/admin/docs"}]
            }
          ]
        end
      end

  A card is a `title`, the `path` a click on it opens, an `icon` (any `hero-*`
  name) and a `color` (a name from `GamendWeb.AdminComponents.colors/0`), an
  optional headline `value`, and `lines`: a string for a plain line,
  `{label, value}` for a figure, `{label, value, path}` for a figure or a bare
  label (`value` nil) that links somewhere.

  The page itself opens with `<.admin_header title="Traffic" icon="hero-chart-bar-solid"
  color="cyan" />` (`GamendWeb.AdminComponents`).

  `cards/0` runs on every dashboard mount, beside core's own queries, so keep
  it to counts. A raise is logged and the module's cards are left out; the
  dashboard still renders.
  """

  @type line :: String.t() | {String.t(), term()} | {String.t(), term(), String.t()}
  @type card :: %{
          required(:title) => String.t(),
          required(:path) => String.t(),
          optional(:icon) => String.t(),
          optional(:color) => String.t(),
          optional(:value) => term(),
          optional(:lines) => [line()]
        }

  @doc "The cards this module adds to `/admin`, in order."
  @callback cards() :: [card()]

  require Logger

  @doc "Every configured module's cards (`config :gamend_web, :admin_cards`)."
  @spec load() :: [card()]
  def load do
    :gamend_web |> Application.get_env(:admin_cards, []) |> Enum.flat_map(&cards_of/1)
  end

  defp cards_of(module) do
    module.cards()
  rescue
    error ->
      Logger.warning("admin cards from #{inspect(module)} failed: " <> Exception.message(error))

      []
  end
end
