defmodule GamendWeb.QuestsLiveFiltersTest do
  @moduledoc """
  The status filters (All, In Progress, Claimable, Completed) each carry an
  icon beside the word.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "every status filter has its icon", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/quests")

    for {status, icon} <- [
          {"", "hero-squares-2x2"},
          {"in_progress", "hero-clock"},
          {"claimable", "hero-gift"},
          {"done", "hero-check-circle"}
        ] do
      assert has_element?(view, ~s(button[phx-value-status="#{status}"] span.#{icon}))
    end
  end
end
