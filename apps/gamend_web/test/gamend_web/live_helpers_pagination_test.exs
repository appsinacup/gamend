defmodule GamendWeb.LiveHelpersPaginationTest do
  @moduledoc """
  The pagination arithmetic every paged LiveView shares, each of these a bug
  a hand-written copy would have.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.LiveHelpers

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  describe "prev_page/2" do
    test "never goes below the first page" do
      assert LiveHelpers.prev_page(socket(%{page: 1})).assigns.page == 1
      assert LiveHelpers.prev_page(socket(%{page: 3})).assigns.page == 2
    end

    test "pages a named assign" do
      assert LiveHelpers.prev_page(socket(%{players_page: 4}), :players_page).assigns.players_page ==
               3
    end
  end

  describe "next_page/3" do
    test "stops at the last page when the total is known" do
      assert LiveHelpers.next_page(socket(%{page: 5, total_pages: 5})).assigns.page == 5
    end

    # tournaments.ex clamped to total_pages with no floor.
    test "never lands on page 0 when there are no pages" do
      assert LiveHelpers.next_page(socket(%{page: 1, total_pages: 0})).assigns.page == 1
    end

    test "is unbounded only when the view does not know the total" do
      assert LiveHelpers.next_page(socket(%{page: 5})).assigns.page == 6
    end

    test "reads the total from the named assign" do
      s = socket(%{notif_page: 2, notif_total_pages: 2})
      assert LiveHelpers.next_page(s, :notif_page, :notif_total_pages).assigns.notif_page == 2
    end

    # A view paging two lists holds `:total_pages` for one and
    # `:records_total_pages` for the other. A fixed `:total_pages` default would
    # have clamped the records list against the wrong total.
    test "derives the total from the page key, not from :total_pages" do
      s = socket(%{records_page: 2, records_total_pages: 9, total_pages: 2})
      assert LiveHelpers.next_page(s, :records_page).assigns.records_page == 3
    end

    test "a named page with no matching total is unbounded" do
      s = socket(%{zzz_unpaired_page: 4})
      assert LiveHelpers.next_page(s, :zzz_unpaired_page).assigns.zzz_unpaired_page == 5
    end
  end

  describe "put_page_size/3" do
    # Eleven copies used String.to_integer/1 here.
    test "a non-numeric size keeps the current one instead of crashing" do
      s = LiveHelpers.put_page_size(socket(%{page: 3, page_size: 50}), "abc")
      assert s.assigns.page_size == 50
      assert s.assigns.page == 1
    end

    test "clamps to the configured maximum" do
      max = Gamend.Limits.get(:max_page_size)
      assert LiveHelpers.put_page_size(socket(%{page: 1}), "999999").assigns.page_size == max
    end

    test "honours a layout's minimum and named assigns" do
      s =
        LiveHelpers.put_page_size(socket(%{groups_page: 4}), "10",
          min: 25,
          size_key: :groups_page_size,
          page_key: :groups_page
        )

      assert s.assigns.groups_page_size == 25
      assert s.assigns.groups_page == 1
    end
  end
end
