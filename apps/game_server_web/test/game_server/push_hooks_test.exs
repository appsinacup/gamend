defmodule GameServer.PushHooksTest do
  use GameServer.DataCase, async: false
  use Oban.Testing, repo: GameServer.Repo

  alias GameServer.AccountsFixtures
  alias GameServer.Push
  alias GameServer.Push.DeliveryWorker

  defmodule VetoHooks do
    use GameServerWeb.TestSupport.NoopHooks

    @impl true
    def before_push_send(user_id, message) do
      send(:push_hooks_test, {:before_push_send, user_id})

      if message["data"]["veto"] == "yes" do
        {:error, :muted}
      else
        {:ok, message}
      end
    end
  end

  defmodule RewriteHooks do
    use GameServerWeb.TestSupport.NoopHooks

    @impl true
    def before_push_send(_user_id, message) do
      {:ok, Map.put(message, "title", "[rewritten] " <> message["title"])}
    end
  end

  defmodule OversizeRewriteHooks do
    use GameServerWeb.TestSupport.NoopHooks

    @impl true
    def before_push_send(_user_id, message) do
      {:ok, Map.put(message, "title", String.duplicate("x", 10_000))}
    end
  end

  defmodule ObserverHooks do
    use GameServerWeb.TestSupport.NoopHooks

    @impl true
    def after_push_sent(user_id, message, result) do
      send(:push_hooks_test, {:after_push_sent, user_id, message, result})
      :ok
    end
  end

  setup do
    Process.register(self(), :push_hooks_test)
    original = Application.get_env(:game_server_core, :hooks_module)

    on_exit(fn ->
      if original,
        do: Application.put_env(:game_server_core, :hooks_module, original),
        else: Application.delete_env(:game_server_core, :hooks_module)
    end)

    :ok
  end

  defp use_hooks(module) do
    Application.put_env(:game_server_core, :hooks_module, module)
  end

  defp register!(user) do
    {:ok, token} =
      Push.register_token(user.id, %{
        "token" => "tok-#{System.unique_integer([:positive])}",
        "platform" => "android"
      })

    token
  end

  test "before_push_send can veto a push per user" do
    use_hooks(VetoHooks)
    user = AccountsFixtures.user_fixture()
    register!(user)

    assert :ok =
             Push.send_to_user(user.id, %{
               "title" => "Hi",
               "data" => %{"veto" => "yes"}
             })

    assert_received {:before_push_send, _}
    assert all_enqueued(worker: DeliveryWorker) == []

    assert :ok = Push.send_to_user(user.id, %{"title" => "Hi"})
    assert [_] = all_enqueued(worker: DeliveryWorker)
  end

  test "before_push_send can rewrite the message" do
    use_hooks(RewriteHooks)
    user = AccountsFixtures.user_fixture()
    register!(user)

    assert :ok = Push.send_to_user(user.id, %{"title" => "Hi"})

    assert [job] = all_enqueued(worker: DeliveryWorker)
    assert job.args["message"]["title"] == "[rewritten] Hi"
  end

  test "a rewrite that breaks the limits drops the push instead of enqueuing it" do
    use_hooks(OversizeRewriteHooks)
    user = AccountsFixtures.user_fixture()
    register!(user)

    assert :ok = Push.send_to_user(user.id, %{"title" => "Hi"})
    assert all_enqueued(worker: DeliveryWorker) == []
  end

  test "after_push_sent observes the delivery outcome" do
    use_hooks(ObserverHooks)
    user = AccountsFixtures.user_fixture()
    token = register!(user)

    args = %{
      "token_id" => token.id,
      "user_id" => user.id,
      "message" => %{"title" => "Hi"}
    }

    assert :ok = perform_job(DeliveryWorker, args)

    assert_received {:after_push_sent, user_id, %{"title" => "Hi"}, result}
    assert user_id == user.id
    assert result["status"] == "delivered"
    assert result["token_id"] == token.id
  end

  test "hooks are blocked from client RPC" do
    assert {:error, :disallowed} = GameServer.Hooks.call(:before_push_send, ["u", %{}])
    assert {:error, :disallowed} = GameServer.Hooks.call(:after_push_sent, ["u", %{}, %{}])
  end

  test "notifications bridge to push after commit" do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()
    {:ok, request} = GameServer.Friends.create_request(sender.id, recipient.id)
    {:ok, _} = GameServer.Friends.accept_friend_request(request.id, recipient)
    register!(recipient)

    {:ok, notification} =
      GameServer.Notifications.send_notification(sender.id, %{
        "user_id" => recipient.id,
        "title" => "Game invite",
        "content" => "Join my lobby!"
      })

    assert [job] = all_enqueued(worker: DeliveryWorker)
    assert job.args["user_id"] == recipient.id
    assert job.args["message"]["title"] == "Game invite"
    assert job.args["message"]["body"] == "Join my lobby!"
    assert job.args["message"]["collapse_key"] == "notif-#{notification.id}"
    assert job.args["message"]["data"]["notification_id"] == notification.id
  end

  test "notifications to a user with no devices enqueue nothing" do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()
    {:ok, request} = GameServer.Friends.create_request(sender.id, recipient.id)
    {:ok, _} = GameServer.Friends.accept_friend_request(request.id, recipient)

    {:ok, _} =
      GameServer.Notifications.send_notification(sender.id, %{
        "user_id" => recipient.id,
        "title" => "Game invite"
      })

    assert all_enqueued(worker: DeliveryWorker) == []
  end

  test "retention prunes stale tokens by updated_at" do
    user = AccountsFixtures.user_fixture()
    token = register!(user)

    days = 271
    stale = DateTime.add(DateTime.utc_now(:second), -days, :day)

    Repo.update_all(GameServer.Push.PushToken,
      set: [updated_at: stale]
    )

    original = Application.get_env(:game_server_core, GameServer.Retention, [])

    Application.put_env(
      :game_server_core,
      GameServer.Retention,
      Keyword.put(original, :push_tokens_days, 270)
    )

    on_exit(fn -> Application.put_env(:game_server_core, GameServer.Retention, original) end)

    results = GameServer.Retention.prune_all()
    assert results.push_tokens >= 1
    assert Push.count_tokens(user.id) == 0
    refute Repo.get(GameServer.Push.PushToken, token.id)
  end
end
