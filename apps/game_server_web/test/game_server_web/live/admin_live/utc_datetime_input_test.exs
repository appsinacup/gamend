defmodule GameServerWeb.AdminLive.UtcDatetimeInputTest do
  @moduledoc """
  A `datetime-local` input submits the browser's wall clock with no offset, so
  binding a form field straight to one stores the admin's local time as if it
  were UTC — an event scheduled for 14:30 firing at 17:30 for an admin three
  hours east. The field the form casts must therefore be the hidden UTC one,
  with the visible input a nameless mirror the hook drives.
  """
  use GameServerWeb.ConnCase, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  test "the form casts the UTC field, not the local one", %{conn: conn, admin: admin} do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/tournaments")

    html = render_click(view, "new_tournament")

    # The named field carries UTC and is hidden; nothing else may claim the name.
    assert html =~ ~s(type="hidden" name="tournament[starts_at]")
    refute html =~ ~s(type="datetime-local" name="tournament[starts_at]")

    # The visible input is a mirror: no name, so the browser's local wall time
    # is never what gets submitted.
    assert html =~ ~s(data-local-mirror-for="tournament_starts_at")
    assert html =~ ~s(phx-hook="LocalDatetimeInput")
  end

  test "an existing value reaches the field as a strict ISO instant" do
    form = to_form(%{"starts_at" => ~U[2026-08-01 23:30:00Z]}, as: :tournament)

    html =
      render_component(&GameServerWeb.CoreComponents.input/1,
        field: form[:starts_at],
        type: "utc-datetime-local"
      )

    # DateTime's own to_string is space-separated, which Safari's Date parser
    # rejects - the admin would just see an empty field.
    assert html =~ ~s(value="2026-08-01T23:30:00Z")
    refute html =~ "2026-08-01 23:30:00Z"
  end
end
