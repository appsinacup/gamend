defmodule GameServerWeb.LoginQuestEventTest do
  @moduledoc """
  Every way of logging in must report the `login` quest event. Only the
  magic-link path did, so a player who signed in with a password or OAuth
  (both go through `UserAuth.log_in_user`) or through the API saw their
  "log in" quest stay at Not started forever.
  """

  use GameServerWeb.ConnCase, async: false

  alias GameServer.AccountsFixtures
  alias GameServer.Quests

  setup do
    {:ok, _} =
      Quests.create_quest(%{
        key: "login_event_probe",
        title: "Welcome aboard",
        reset: "never",
        objectives: [%{event: "login", target: 1}]
      })

    user = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    %{user: user}
  end

  defp wait_for_progress(user_id, tries \\ 40) do
    entry =
      Quests.list_user_quests(user_id, [])
      |> Enum.find(&(&1.quest.key == "login_event_probe"))

    cond do
      entry && entry.progress != nil ->
        entry.progress

      tries == 0 ->
        nil

      true ->
        Process.sleep(50)
        wait_for_progress(user_id, tries - 1)
    end
  end

  test "a web password login progresses the login quest", %{conn: conn, user: user} do
    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => AccountsFixtures.valid_user_password()}
      })

    assert redirected_to(conn)

    progress = wait_for_progress(user.id)
    assert progress, "no quest progress after a password login"
    assert progress.status in ["completed", "claimed"]
  end

  test "an API password login progresses the login quest", %{conn: conn, user: user} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/login", %{
        "email" => user.email,
        "password" => AccountsFixtures.valid_user_password()
      })

    assert %{"data" => %{"access_token" => _}} = json_response(conn, 200)

    progress = wait_for_progress(user.id)
    assert progress, "no quest progress after an API login"
    assert progress.status in ["completed", "claimed"]
  end
end
