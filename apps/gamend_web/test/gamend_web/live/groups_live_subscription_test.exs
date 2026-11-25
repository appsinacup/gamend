defmodule GamendWeb.GroupsLiveSubscriptionTest do
  @moduledoc """
  One group page, one subscription.

  `/groups` selects a group with `push_patch/2`, so opening one, going back to
  the list and opening it again all happen in the SAME LiveView process. A
  `handle_params/3` calling `Groups.subscribe_group/1` every time with nothing
  dropping the previous registration would, since `Phoenix.PubSub` is a
  duplicate registry, make the third visit run `load_groups/1` three times per
  `{:member_joined, …}`: three identical queries per event, growing for as
  long as the reader stays on the page.

  Counted through the PubSub registry rather than through renders, because a
  duplicated `load_groups/1` produces byte-identical HTML.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Groups

  setup :register_and_log_in_user

  defp subscriptions(topic, pid) do
    Gamend.PubSub
    |> Registry.lookup(topic)
    |> Enum.count(fn {subscriber, _value} -> subscriber == pid end)
  end

  defp group!(user) do
    {:ok, group} =
      Groups.create_group(user.id, %{
        "title" => "subs-#{System.unique_integer([:positive])}",
        "type" => "public"
      })

    group
  end

  test "re-opening the same group does not stack subscriptions", %{conn: conn, user: user} do
    group = group!(user)
    topic = "group:#{group.id}"

    {:ok, view, _html} = live(conn, ~p"/groups")
    assert subscriptions(topic, view.pid) == 0

    # Open it, back to the list, open it again — three `handle_params` passes in
    # one process.
    render_patch(view, ~p"/groups/#{group.id}")
    assert subscriptions(topic, view.pid) == 1

    render_patch(view, ~p"/groups")
    assert subscriptions(topic, view.pid) == 0

    render_patch(view, ~p"/groups/#{group.id}")
    render_patch(view, ~p"/groups/#{group.id}")
    assert subscriptions(topic, view.pid) == 1
  end

  test "opening a second group drops the first one's subscription", %{conn: conn, user: user} do
    first = group!(user)
    second = group!(user)

    {:ok, view, _html} = live(conn, ~p"/groups/#{first.id}")
    assert subscriptions("group:#{first.id}", view.pid) == 1

    render_patch(view, ~p"/groups/#{second.id}")

    assert subscriptions("group:#{second.id}", view.pid) == 1
    assert subscriptions("group:#{first.id}", view.pid) == 0
  end
end
