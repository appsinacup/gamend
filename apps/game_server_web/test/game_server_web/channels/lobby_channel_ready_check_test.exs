defmodule GameServerWeb.LobbyChannelReadyCheckTest do
  use ExUnit.Case
  import Phoenix.ChannelTest

  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.ReadyChecks
  alias GameServer.ReadyChecks.Check
  alias GameServerWeb.Auth.Guardian

  @endpoint GameServerWeb.Endpoint

  setup tags do
    GameServer.DataCase.setup_sandbox(tags)

    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "ready-channel", host_id: host.id})
    {:ok, _} = Lobbies.join_lobby(member, lobby.id)

    {:ok, token, _} = Guardian.encode_and_sign(member)
    {:ok, socket} = connect(GameServerWeb.UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "lobby:#{lobby.id}", %{})

    # The lobby payload pushed on join.
    assert_push "updated", _

    %{host: host, member: member, lobby: lobby, socket: socket}
  end

  test "opening pushes the check to the lobby topic", ctx do
    {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], opened_by: ctx.host.id)

    assert_push "ready_check_started", payload
    assert payload.kind == "ready"
    assert payload.total == 2
    assert payload.ready_count == 1
    assert length(payload.participants) == 2
    # Serialized per socket, so each member sees their own state.
    assert payload.your_state == "pending"
  end

  test "an answer pushes an update, and the pass is its own event", ctx do
    {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], opened_by: ctx.host.id)
    assert_push "ready_check_started", _

    {:ok, _} = ReadyChecks.respond(ctx.member, false)
    assert_push "ready_check_updated", %{status: "pending", your_state: "declined"}

    {:ok, _} = ReadyChecks.respond(ctx.member, true)
    assert_push "ready_check_passed", %{status: "passed", ready_count: 2}
  end

  test "a timeout pushes the failure with its reason", ctx do
    {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])
    assert_push "ready_check_started", _

    GameServer.Repo.update_all(Check,
      set: [deadline_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert ReadyChecks.expire(ReadyChecks.get_check(check.id)) == :ok
    assert_push "ready_check_failed", %{status: "failed", reason: "timeout"}
  end

  test "cancelling pushes a failure with reason cancelled", ctx do
    {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])
    assert_push "ready_check_started", _

    {:ok, _} = ReadyChecks.cancel(check)
    assert_push "ready_check_failed", %{status: "cancelled", reason: "cancelled"}
  end
end
