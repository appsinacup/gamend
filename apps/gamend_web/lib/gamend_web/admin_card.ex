defmodule GamendWeb.AdminCard do
  @moduledoc """
  A host's entries on the admin dashboard (`/admin`).

  Core draws a tile and a card for each of its own admin pages. A host's admin
  pages (its traffic, its tools) are the host's to describe, so it lists
  modules that answer `cards/0`, and the dashboard draws them after core's:

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
              icon: "hero-chart-bar",
              color: "cyan",
              value: 120,
              lines: ["Visits today", {"Humans", 80}, {"Docs", nil, "/admin/docs"}]
            }
          ]
        end
      end

  A card is a `title`, the `path` its "View" link opens, an `icon` (any
  `hero-*` name) and a `color` (a name from `GamendWeb.AdminComponents.colors/0`),
  an optional headline `value`, and `lines`: a string for a plain line,
  `{label, value}` for a figure, `{label, value, path}` for a figure or a bare
  label (`value` nil) that links somewhere.

  Each card is also a tile in the menu above the cards, with its `value`
  beside the name. A module whose menu is not one tile per card answers
  `links/0` as well, and those are its tiles instead:

      @impl true
      def links do
        [%{title: "Docs", path: "/admin/docs", icon: "hero-book-open", color: "sky"}]
      end

  The page itself opens with `<.admin_header title="Traffic" icon="hero-chart-bar"
  color="cyan" />` (`GamendWeb.AdminComponents`).

  `cards/0` runs on every dashboard mount, beside core's own queries, so keep
  it to counts. A raise is logged and the module's entries are left out; the
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
  @type link :: %{
          required(:title) => String.t(),
          required(:path) => String.t(),
          optional(:icon) => String.t(),
          optional(:color) => String.t(),
          optional(:value) => term()
        }

  @doc "The cards this module adds to `/admin`, in order."
  @callback cards() :: [card()]

  @doc "The module's menu tiles, when they are not one per card."
  @callback links() :: [link()]

  @optional_callbacks links: 0

  require Logger

  @doc """
  Every configured module's cards and menu tiles
  (`config :gamend_web, :admin_cards`).
  """
  @spec load() :: %{cards: [card()], links: [link()]}
  def load do
    entries = :gamend_web |> Application.get_env(:admin_cards, []) |> Enum.map(&entries_of/1)

    %{cards: Enum.flat_map(entries, & &1.cards), links: Enum.flat_map(entries, & &1.links)}
  end

  defp entries_of(module) do
    cards = module.cards()

    links =
      if function_exported?(module, :links, 0),
        do: module.links(),
        else: Enum.map(cards, &Map.drop(&1, [:lines]))

    %{cards: cards, links: links}
  rescue
    error ->
      Logger.warning("admin cards from #{inspect(module)} failed: " <> Exception.message(error))

      %{cards: [], links: []}
  end
end
