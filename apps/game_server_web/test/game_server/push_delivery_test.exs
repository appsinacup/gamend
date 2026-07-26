defmodule GameServer.PushDeliveryTest do
  use GameServer.DataCase, async: false
  use Oban.Testing, repo: GameServer.Repo

  alias GameServer.AccountsFixtures
  alias GameServer.Push
  alias GameServer.Push.APNSDispatcher
  alias GameServer.Push.DeliveryWorker
  alias GameServer.Push.FanoutWorker
  alias GameServer.Push.Message
  alias GameServer.Push.Providers.APNs
  alias GameServer.Push.Providers.FCM
  alias GameServer.Push.Providers.Log
  alias Pigeon.APNS.Notification, as: APNSNotification
  alias Pigeon.FCM.Notification, as: FCMNotification

  defmodule InvalidProvider do
    @behaviour GameServer.Push.Provider
    @impl true
    def deliver(_message, _token), do: {:invalid, :unregistered}
    @impl true
    def configured?, do: true
  end

  defmodule TransientProvider do
    @behaviour GameServer.Push.Provider
    @impl true
    def deliver(_message, _token), do: {:error, :transient, :service_unavailable}
    @impl true
    def configured?, do: true
  end

  defmodule PermanentProvider do
    @behaviour GameServer.Push.Provider
    @impl true
    def deliver(_message, _token), do: {:error, :permanent, :sender_id_mismatch}
    @impl true
    def configured?, do: true
  end

  defp put_push_env(overrides) do
    old = Application.get_env(:game_server_core, GameServer.Push, [])
    Application.put_env(:game_server_core, GameServer.Push, Keyword.merge(old, overrides))
    on_exit(fn -> Application.put_env(:game_server_core, GameServer.Push, old) end)
  end

  defp swap_provider(name, module) do
    old = Application.get_env(:game_server_core, GameServer.Push, [])
    providers = Map.put(old[:providers] || %{}, name, module)
    put_push_env(providers: providers)
  end

  defp register!(user, attrs) do
    {:ok, token} =
      Push.register_token(
        user.id,
        Map.merge(%{"token" => "tok-#{System.unique_integer([:positive])}"}, attrs)
      )

    token
  end

  defp delivery_args(token, message_attrs) do
    {:ok, message} = Message.new(message_attrs)

    %{
      "token_id" => token.id,
      "user_id" => token.user_id,
      "message" => Message.to_map(message)
    }
  end

  describe "Message.new/1" do
    test "validates and normalizes" do
      assert {:ok, message} =
               Message.new(%{title: "Hi", body: "There", data: %{"k" => "v"}, badge: 3})

      assert message.title == "Hi"

      round_tripped = message |> Message.to_map() |> Message.from_map()
      assert round_tripped == message
    end

    test "rejects missing or oversized fields" do
      assert {:error, %{title: _}} = Message.new(%{})
      assert {:error, %{title: _}} = Message.new(%{title: ""})

      long_title = String.duplicate("x", GameServer.Limits.get(:max_push_title) + 1)
      assert {:error, %{title: _}} = Message.new(%{title: long_title})

      big_value = String.duplicate("x", GameServer.Limits.get(:max_push_data_size) + 1)
      assert {:error, %{data: _}} = Message.new(%{title: "t", data: %{"k" => big_value}})

      assert {:error, %{badge: _}} = Message.new(%{title: "t", badge: -1})
      assert {:error, %{sound: _}} = Message.new(%{title: "t", sound: 5})
    end

    test "caps are bytes, not characters" do
      # 100 CJK chars = 300 bytes: passes a 255-char reading, must fail a
      # byte reading of max_push_title (255).
      multibyte_title = String.duplicate("語", 100)
      assert {:error, %{title: _}} = Message.new(%{title: multibyte_title})

      max_body = GameServer.Limits.get(:max_push_body)
      multibyte_body = String.duplicate("語", div(max_body, 3) + 1)
      assert {:error, %{body: _}} = Message.new(%{title: "t", body: multibyte_body})
    end

    test "truncate/2 cuts to bytes without splitting characters" do
      assert Message.truncate("hello", 10) == "hello"
      assert Message.truncate("hello", 3) == "hel"

      # Each 語 is 3 bytes; a 4-byte budget must not tear one apart.
      truncated = Message.truncate("語語", 4)
      assert truncated == "語"
      assert String.valid?(truncated)
      assert Message.truncate("語語", 2) == ""
    end
  end

  describe "provider_for/1" do
    test "falls back to Log when the provider dispatcher is not running" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})

      assert Push.provider_for(token) == Log
    end

    test "routes to the configured provider module when it is configured" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})

      swap_provider("fcm", InvalidProvider)
      assert Push.provider_for(token) == InvalidProvider
    end

    test "adapter: :log overrides everything (GAMEND_PUSH_ADAPTER=log)" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})

      swap_provider("fcm", InvalidProvider)
      put_push_env(adapter: :log)

      assert Push.provider_for(token) == Log
    end
  end

  describe "DeliveryWorker" do
    test "delivers via the Log provider and bumps last_used_at" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})
      assert token.last_used_at == nil

      assert :ok = perform_job(DeliveryWorker, delivery_args(token, %{title: "Hello"}))

      assert [%{last_used_at: %DateTime{}}] = Push.live_tokens(user.id)
    end

    test "delivers through a Sandbox-backed dispatcher end to end" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "ios", "provider" => "apns"})

      start_supervised!({APNSDispatcher, adapter: Pigeon.Sandbox})
      assert APNs.configured?()
      assert Push.provider_for(token) == APNs

      assert :ok = perform_job(DeliveryWorker, delivery_args(token, %{title: "Hello"}))
      assert [%{last_used_at: %DateTime{}}] = Push.live_tokens(user.id)
    end

    test "disables the token when the provider reports it dead" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})
      swap_provider("fcm", InvalidProvider)

      assert :ok = perform_job(DeliveryWorker, delivery_args(token, %{title: "Hello"}))

      assert Push.live_tokens(user.id) == []
      refute Push.user_has_live_tokens?(user.id)
    end

    test "returns an error for transient failures so Oban retries" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})
      swap_provider("fcm", TransientProvider)

      assert {:error, :service_unavailable} =
               perform_job(DeliveryWorker, delivery_args(token, %{title: "Hello"}))

      # Still live: transient failures never disable a token.
      assert [_] = Push.live_tokens(user.id)
    end

    test "cancels on permanent configuration errors" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})
      swap_provider("fcm", PermanentProvider)

      assert {:cancel, :sender_id_mismatch} =
               perform_job(DeliveryWorker, delivery_args(token, %{title: "Hello"}))
    end

    test "no-ops when the token was removed or disabled since enqueue" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})
      args = delivery_args(token, %{title: "Hello"})

      :ok = Push.disable_token(token.token)
      assert :ok = perform_job(DeliveryWorker, args)

      {:ok, _} = Push.delete_token(user.id, token.id)
      assert :ok = perform_job(DeliveryWorker, args)
    end
  end

  describe "send_to_user/3 and send_to_users/3" do
    test "enqueues one delivery job per live token" do
      user = AccountsFixtures.user_fixture()
      register!(user, %{"platform" => "android", "device_id" => "d1"})
      register!(user, %{"platform" => "ios", "device_id" => "d2"})
      disabled = register!(user, %{"platform" => "web", "device_id" => "d3"})
      :ok = Push.disable_token(disabled.token)

      assert :ok = Push.send_to_user(user.id, %{title: "Hi", body: "There"})

      enqueued = all_enqueued(worker: DeliveryWorker)
      assert length(enqueued) == 2
      assert Enum.all?(enqueued, &(&1.args["message"]["title"] == "Hi"))
    end

    test "enqueues nothing when the user has no devices" do
      user = AccountsFixtures.user_fixture()

      assert :ok = Push.send_to_user(user.id, %{title: "Hi"})
      assert all_enqueued(worker: DeliveryWorker) == []
    end

    test "rejects an invalid message" do
      user = AccountsFixtures.user_fixture()
      assert {:error, %{title: _}} = Push.send_to_user(user.id, %{})
    end

    test "small multi-user sends expand inline" do
      users = for _ <- 1..3, do: AccountsFixtures.user_fixture()
      for user <- users, do: register!(user, %{"platform" => "android"})

      assert :ok = Push.send_to_users(Enum.map(users, & &1.id), %{title: "Patch notes"})

      assert length(all_enqueued(worker: DeliveryWorker)) == 3
      assert all_enqueued(worker: FanoutWorker) == []
    end

    test "large multi-user sends enqueue a fan-out job that expands on perform" do
      users = for _ <- 1..3, do: AccountsFixtures.user_fixture()
      for user <- users, do: register!(user, %{"platform" => "android"})

      # 101 ids crosses the inline threshold; the extra ids have no tokens.
      padded_ids = Enum.map(users, & &1.id) ++ List.duplicate(hd(users).id, 98)

      assert :ok = Push.send_to_users(padded_ids, %{title: "Patch notes"})
      assert all_enqueued(worker: DeliveryWorker) == []
      assert [fanout] = all_enqueued(worker: FanoutWorker)

      assert :ok = perform_job(FanoutWorker, fanout.args)
      assert length(all_enqueued(worker: DeliveryWorker)) == 3
    end
  end

  describe "provider response classification" do
    test "APNs" do
      assert :ok = APNs.classify(%APNSNotification{response: :success})

      assert {:invalid, :unregistered} =
               APNs.classify(%APNSNotification{response: :unregistered})

      assert {:invalid, :bad_device_token} =
               APNs.classify(%APNSNotification{response: :bad_device_token})

      assert {:error, :permanent, :bad_topic} =
               APNs.classify(%APNSNotification{response: :bad_topic})

      assert {:error, :transient, :too_many_requests} =
               APNs.classify(%APNSNotification{response: :too_many_requests})

      assert {:error, :transient, :expired_provider_token} =
               APNs.classify(%APNSNotification{response: :expired_provider_token})
    end

    test "FCM" do
      assert :ok =
               FCM.classify(%FCMNotification{target: {:token, "t"}, response: :success})

      assert {:invalid, :unregistered} =
               FCM.classify(%FCMNotification{
                 target: {:token, "t"},
                 response: :unregistered
               })

      assert {:error, :permanent, :sender_id_mismatch} =
               FCM.classify(%FCMNotification{
                 target: {:token, "t"},
                 response: :sender_id_mismatch
               })

      assert {:error, :transient, :unavailable} =
               FCM.classify(%FCMNotification{
                 target: {:token, "t"},
                 response: :unavailable
               })
    end
  end

  describe "notification payload shape" do
    test "APNs notification carries alert, badge, sound, collapse id and custom data" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "ios"})

      {:ok, message} =
        Message.new(%{
          title: "Hi",
          body: "There",
          badge: 2,
          sound: "ping",
          collapse_key: "chat",
          image: "https://example.com/i.png",
          data: %{"kind" => "chat"}
        })

      notification = APNs.build_notification(message, token)

      assert notification.device_token == token.token
      assert notification.collapse_id == "chat"
      aps = notification.payload["aps"]
      assert aps["alert"] == %{"title" => "Hi", "body" => "There"}
      assert aps["badge"] == 2
      assert aps["sound"] == "ping"
      assert notification.payload["kind"] == "chat"
      assert notification.payload["image"] == "https://example.com/i.png"
    end

    test "FCM refuses a combined payload past its wire limit before sending" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})

      # Individually within caps, combined past FCM's 4096-byte message limit.
      {:ok, message} =
        Message.new(%{
          title: String.duplicate("t", 250),
          body: String.duplicate("b", 3_900),
          data: %{"k" => String.duplicate("d", 3_000)}
        })

      assert {:error, :permanent, :payload_too_large} =
               FCM.deliver(message, token)
    end

    test "FCM notification stringifies data values and carries android options" do
      user = AccountsFixtures.user_fixture()
      token = register!(user, %{"platform" => "android"})

      {:ok, message} =
        Message.new(%{
          title: "Hi",
          sound: "ping",
          collapse_key: "chat",
          data: %{"count" => 3, "kind" => "chat"}
        })

      notification = FCM.build_notification(message, token)

      assert notification.target == {:token, token.token}
      assert notification.notification == %{"title" => "Hi"}
      assert notification.data == %{"count" => "3", "kind" => "chat"}
      assert notification.android["collapse_key"] == "chat"
      assert notification.android["notification"] == %{"sound" => "ping"}
    end
  end
end
