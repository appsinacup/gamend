defmodule GamendWeb.AdminCardTest do
  @moduledoc """
  What a host's `GamendWeb.AdminCard` module adds to `/admin`: its cards, and
  one tile per card unless it names its own.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias GamendWeb.AdminCard

  defmodule CardsOnly do
    @behaviour GamendWeb.AdminCard

    @impl true
    def cards do
      [
        %{
          title: "Builds",
          path: "/admin/builds",
          icon: "hero-cube",
          color: "violet",
          value: 2,
          lines: ["Running or queued"]
        }
      ]
    end
  end

  defmodule WithLinks do
    @behaviour GamendWeb.AdminCard

    @impl true
    def cards, do: [%{title: "Tools", path: "/admin/docs"}]

    @impl true
    def links do
      [
        %{title: "Docs", path: "/admin/docs", icon: "hero-book-open", color: "sky"},
        %{title: "Changelog", path: "/admin/changelog"}
      ]
    end
  end

  defmodule Broken do
    @behaviour GamendWeb.AdminCard

    @impl true
    def cards, do: raise("no table yet")
  end

  setup do
    previous = Application.get_env(:gamend_web, :admin_cards)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, :admin_cards, previous),
        else: Application.delete_env(:gamend_web, :admin_cards)
    end)
  end

  defp load(modules) do
    Application.put_env(:gamend_web, :admin_cards, modules)
    AdminCard.load()
  end

  test "a card is also a tile, with its icon, colour and figure" do
    assert %{cards: [card], links: [link]} = load([CardsOnly])

    assert card.lines == ["Running or queued"]
    assert link == Map.delete(card, :lines)
  end

  test "a module with links/0 decides its own tiles" do
    assert %{cards: [%{title: "Tools"}], links: links} = load([WithLinks])

    assert Enum.map(links, & &1.title) == ["Docs", "Changelog"]
  end

  test "a module that raises is logged and left out; the others still draw" do
    log =
      capture_log(fn ->
        assert %{cards: [%{title: "Builds"}], links: [_]} = load([Broken, CardsOnly])
      end)

    assert log =~ "no table yet"
  end

  test "no modules, nothing added" do
    assert load([]) == %{cards: [], links: []}
  end
end
