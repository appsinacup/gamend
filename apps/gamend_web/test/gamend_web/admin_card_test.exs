defmodule GamendWeb.AdminCardTest do
  @moduledoc """
  What a host's `GamendWeb.AdminCard` modules add to `/admin`: their cards.
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

  test "a module's cards come back as it wrote them" do
    assert [card] = load([CardsOnly])

    assert card.lines == ["Running or queued"]
  end

  test "a module that raises is logged and left out; the others still draw" do
    log =
      capture_log(fn ->
        assert [%{title: "Builds"}] = load([Broken, CardsOnly])
      end)

    assert log =~ "no table yet"
  end

  test "no modules, nothing added" do
    assert load([]) == []
  end
end
