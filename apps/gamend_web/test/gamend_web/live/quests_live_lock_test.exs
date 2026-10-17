defmodule GamendWeb.QuestsLiveLockTest do
  @moduledoc """
  `:quest_lock_filter` — the host's "you can see this, but it is not yours to
  claim yet".

  The state the page could not express before: `host_visible/2` keeps a quest or
  drops it, and `hidden` is a column that draws "???" over the very title a
  premium offer is made of. A quest shown with its real name and live progress
  and NO claim button is the third thing, and the failure it prevents is a
  Claim the server then refuses.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Quests

  defmodule LockAll do
    @moduledoc false
    def label(_user_id, %{key: "locked_quest"}), do: "Crown"
    def label(_user_id, _quest), do: nil
  end

  defmodule LockBlank do
    @moduledoc false
    def label(_user_id, _quest), do: "   "
  end

  setup do
    for {key, title} <- [{"locked_quest", "Sell ten crates"}, {"free_quest", "Log in today"}] do
      {:ok, _} =
        Quests.create_quest(%{
          key: key,
          title: title,
          description: "Do the thing.",
          category: "Daily",
          reset: "daily",
          objectives: [%{event: "login", target: 1}]
        })
    end

    on_exit(fn -> Application.delete_env(:gamend_core, :quest_lock_filter) end)
    :ok
  end

  defp page(conn) do
    {:ok, _view, html} = live(conn, ~p"/quests")
    html
  end

  defp signed_in(conn), do: log_in_user(conn, Gamend.AccountsFixtures.user_fixture())

  defp card(html, title) do
    html |> String.split(title) |> Enum.at(1, "") |> String.slice(0, 1800)
  end

  test "with no filter registered nothing is locked", %{conn: conn} do
    html = conn |> signed_in() |> page()

    assert html =~ "Sell ten crates"
    refute html =~ "hero-lock-closed-solid"
  end

  test "a locked quest shows the host's reason and no Claim button", %{conn: conn} do
    Application.put_env(:gamend_core, :quest_lock_filter, {LockAll, :label})

    # Logging in fires `login`, so both quests finish and would both offer a
    # Claim — which is exactly the button the locked one must not have.
    html = conn |> signed_in() |> page()

    locked = card(html, "Sell ten crates")
    assert locked =~ "Crown"
    assert locked =~ "hero-lock-closed-solid"

    refute locked =~ ~s(phx-value-key="locked_quest"),
           "a locked quest offered a Claim the server would refuse"

    free = card(html, "Log in today")
    assert free =~ ~s(phx-value-key="free_quest"), "the unlocked quest still claims normally"
    refute free =~ "hero-lock-closed-solid"
  end

  test "a locked quest keeps its real title and is not a ??? teaser", %{conn: conn} do
    Application.put_env(:gamend_core, :quest_lock_filter, {LockAll, :label})

    html = conn |> signed_in() |> page()

    assert html =~ "Sell ten crates", "the offer IS the title; hiding it is what this replaces"
    refute html =~ "???"
  end

  test "the Claimable count does not count what it cannot offer", %{conn: conn} do
    Application.put_env(:gamend_core, :quest_lock_filter, {LockAll, :label})

    html = conn |> signed_in() |> page()

    # Both quests completed on login; only the free one is claimable, so the
    # Claimable chip must say one. Counting two sends the reader hunting for a
    # button that is deliberately not there.
    assert html =~ ~r/<span class="badge badge-sm">\s*1\s*<\/span>/
  end

  test "a blank label is not a lock", %{conn: conn} do
    Application.put_env(:gamend_core, :quest_lock_filter, {LockBlank, :label})

    html = conn |> signed_in() |> page()

    refute html =~ "hero-lock-closed-solid",
           "an empty badge is worse than none, and it is what a stubbed filter returns"
  end

  test "a signed-out visitor is never told a quest is locked", %{conn: conn} do
    Application.put_env(:gamend_core, :quest_lock_filter, {LockAll, :label})

    # The claim column is signed-in only, and a guest has no account for the
    # lock to be about.
    refute page(conn) =~ "hero-lock-closed-solid"
  end
end
