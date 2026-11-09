defmodule Gamend.PaymentsTest do
  use Gamend.DataCase
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.ProviderEvent
  alias Gamend.Payments.Purchase

  defmodule StoreAdapter do
    def validate_purchase(_user, attrs) do
      attrs = normalize(attrs)

      {:ok,
       %{
         "product_id" => attrs["product_id"],
         "transaction_id" => attrs["transaction_id"],
         "original_transaction_id" => attrs["original_transaction_id"],
         "status" => attrs["status"] || "completed",
         "quantity" => attrs["quantity"] || 1,
         "currency" => attrs["currency"],
         "amount" => attrs["amount"],
         "environment" => attrs["environment"] || "test",
         "raw_payload" => attrs
       }}
    end

    def verify_webhook(raw_body, _authorization), do: Jason.decode(raw_body)
    def verify_notification(raw_body), do: Jason.decode(raw_body)

    defp normalize(attrs) do
      Map.new(attrs, fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        pair -> pair
      end)
    end
  end

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  defmodule CapturePaymentHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def after_purchase_fulfilled(purchase) do
      send(hook_pid(), {:payment_purchase_fulfilled, purchase.id, purchase.user_id})
      send(hook_pid(), {:payment_hook_item_grant, purchase.user_id, purchase.product_id})
      :ok
    end

    @impl true
    def after_purchase_revoked(purchase) do
      send(hook_pid(), {:payment_purchase_revoked, purchase.id, purchase.user_id})
      :ok
    end

    @impl true
    def after_entitlement_changed(entitlement) do
      send(
        hook_pid(),
        {:payment_entitlement_changed, entitlement.key, entitlement.status, entitlement.user_id}
      )

      :ok
    end

    defp hook_pid do
      :persistent_term.get({__MODULE__, :pid})
    end
  end

  setup do
    original_adapters = Application.get_env(:gamend_core, :payment_provider_adapters)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(:gamend_core, :payment_provider_adapters,
      apple: StoreAdapter,
      google: StoreAdapter,
      steam: StoreAdapter
    )

    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:payment_provider_adapters, original_adapters)
      restore_env(:hooks_module, original_hooks)
    end)

    :ok
  end

  describe "fulfillment" do
    test "consumable purchases complete once and rely on hooks for game grants" do
      capture_payment_hooks()

      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_consumable_provider_product("stripe", "price_coins")

      assert {:ok, %Purchase{} = purchase} =
               Payments.create_purchase(user, provider_product, %{
                 "provider_transaction_id" => "cs_test_consumable"
               })

      assert {:ok, %Purchase{status: "completed"} = completed} =
               Payments.fulfill_purchase(purchase, %{"provider" => "stripe"})

      assert Repo.aggregate(Entitlement, :count, :id) == 0
      assert_receive {:payment_purchase_fulfilled, purchase_id, user_id}, 1_000
      assert purchase_id == purchase.id
      assert user_id == user.id

      assert_receive {:payment_hook_item_grant, ^user_id, product_id}, 1_000
      assert product_id == provider_product.product_id

      assert {:ok, %Purchase{status: "completed"}} = Payments.fulfill_purchase(completed)
      assert Repo.aggregate(Entitlement, :count, :id) == 0
    end

    test "entitlement purchases create one active entitlement and revoke cleanly" do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_entitlement_provider_product("google", "battle_pass")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "google_tx_entitlement"
        })

      assert {:ok, completed} = Payments.fulfill_purchase(purchase)
      assert Payments.has_entitlement?(user.id, "battle_pass") == true

      assert {:ok, _completed_again} = Payments.fulfill_purchase(completed)
      assert Repo.aggregate(Entitlement, :count, :id) == 1

      assert {:ok, revoked} = Payments.revoke_purchase(completed, %{"reason" => "refund"})
      assert revoked.status == "revoked"
      assert Payments.has_entitlement?(user.id, "battle_pass") == false
    end

    test "default payment hooks mirror purchase and entitlement state into user metadata" do
      use_default_payment_hooks()

      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_entitlement_provider_product("stripe", "battle_pass")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "cs_metadata_entitlement"
        })

      assert {:ok, completed} = Payments.fulfill_purchase(purchase)

      entitlement = Repo.get_by!(Entitlement, user_id: user.id, key: "battle_pass")
      purchase_id = to_string(purchase.id)
      entitlement_id = to_string(entitlement.id)

      eventually(fn ->
        metadata = Accounts.get_user!(user.id).metadata || %{}

        assert get_in(metadata, ["payments", "purchase_ids", purchase_id]) == true
        assert get_in(metadata, ["payments", "entitlements", "battle_pass"]) == true
        assert get_in(metadata, ["payments", "entitlement_ids", entitlement_id]) == true

        assert get_in(metadata, ["payments", "entitlement_details", "battle_pass", "active"]) ==
                 true

        assert get_in(metadata, ["payments", "entitlement_details", "battle_pass", "status"]) ==
                 "active"
      end)

      assert {:ok, _revoked} = Payments.revoke_purchase(completed, %{"reason" => "refund"})

      eventually(fn ->
        metadata = Accounts.get_user!(user.id).metadata || %{}

        assert get_in(metadata, ["payments", "purchase_ids", purchase_id]) == false
        assert get_in(metadata, ["payments", "entitlements", "battle_pass"]) == false
        assert get_in(metadata, ["payments", "entitlement_ids", entitlement_id]) == false

        assert get_in(metadata, ["payments", "entitlement_details", "battle_pass", "active"]) ==
                 false

        assert get_in(metadata, ["payments", "entitlement_details", "battle_pass", "status"]) ==
                 "revoked"
      end)
    end

    test "subscription purchases create entitlement metadata with expiry" do
      use_default_payment_hooks()

      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_subscription_provider_product("stripe", "premium")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "cs_metadata_subscription"
        })

      assert {:ok, _completed} = Payments.fulfill_purchase(purchase)

      eventually(fn ->
        metadata = Accounts.get_user!(user.id).metadata || %{}
        details = get_in(metadata, ["payments", "entitlement_details", "premium_subscription"])

        assert get_in(metadata, ["payments", "entitlements", "premium_subscription"]) == true
        assert details["active"] == true
        assert details["status"] == "active"
        assert is_binary(details["expires_at"])
      end)
    end
  end

  describe "provider events" do
    test "provider events are deduped by provider and event id" do
      assert {:ok, %ProviderEvent{} = event, true} =
               Payments.record_provider_event(
                 "stripe",
                 "evt_1",
                 "checkout.session.completed",
                 %{}
               )

      assert {:ok, %ProviderEvent{} = duplicate, false} =
               Payments.record_provider_event(
                 "stripe",
                 "evt_1",
                 "checkout.session.completed",
                 %{}
               )

      assert duplicate.id == event.id
      assert Repo.aggregate(ProviderEvent, :count, :id) == 1
    end
  end

  describe "provider webhook processing and hooks" do
    test "fake Google subscription events grant, hook, dedupe, and revoke subscription" do
      capture_payment_hooks()

      user = AccountsFixtures.user_fixture()

      {_product, provider_product} =
        create_subscription_provider_product("google", "premium_monthly")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "GPA.subscription.1",
          "provider_original_transaction_id" => "google_sub_token_1"
        })

      activated_body =
        Jason.encode!(%{
          "message_id" => "google_msg_subscription_activated",
          "subscriptionNotification" => %{
            "purchaseToken" => "google_sub_token_1",
            "notificationType" => 2
          }
        })

      assert {:ok, :processed} = Payments.handle_google_webhook(activated_body, nil)

      completed = Payments.get_purchase(purchase.id)
      assert completed.status == "completed"
      assert Payments.has_entitlement?(user.id, "premium_subscription") == true

      assert_receive {:payment_purchase_fulfilled, purchase_id, user_id}, 1_000
      assert purchase_id == purchase.id
      assert user_id == user.id

      assert_receive {:payment_entitlement_changed, "premium_subscription", "active", ^user_id},
                     1_000

      assert_receive {:payment_hook_item_grant, ^user_id, product_id}, 1_000
      assert product_id == provider_product.product_id

      assert {:ok, :duplicate} = Payments.handle_google_webhook(activated_body, nil)
      assert Repo.aggregate(Entitlement, :count, :id) == 1

      revoked_body =
        Jason.encode!(%{
          "message_id" => "google_msg_subscription_revoked",
          "subscriptionNotification" => %{
            "purchaseToken" => "google_sub_token_1",
            "notificationType" => 13
          }
        })

      assert {:ok, :processed} = Payments.handle_google_webhook(revoked_body, nil)

      revoked = Payments.get_purchase(purchase.id)
      assert revoked.status == "revoked"
      assert Payments.has_entitlement?(user.id, "premium_subscription") == false

      assert_receive {:payment_purchase_revoked, ^purchase_id, ^user_id}, 1_000

      assert_receive {:payment_entitlement_changed, "premium_subscription", "revoked", ^user_id},
                     1_000
    end
  end

  describe "store validation" do
    test "validated receipts create fulfilled purchases and reject replay across users" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_consumable_provider_product("apple", "coins_pack")

      attrs = %{
        "product_id" => provider_product.external_id,
        "transaction_id" => "apple_tx_1",
        "currency" => "USD",
        "amount" => 199,
        "environment" => "test"
      }

      assert {:ok, %{purchase: %Purchase{} = purchase, seen_before: false}} =
               Payments.validate_store_purchase(user, "apple", attrs)

      assert purchase.status == "completed"
      assert purchase.provider_transaction_id == "apple_tx_1"
      assert Repo.aggregate(Entitlement, :count, :id) == 0

      assert {:ok, %{purchase: same_purchase, seen_before: true}} =
               Payments.validate_store_purchase(user, "apple", attrs)

      assert same_purchase.id == purchase.id
      assert Repo.aggregate(Entitlement, :count, :id) == 0

      assert {:error, :receipt_already_used} =
               Payments.validate_store_purchase(other_user, "apple", attrs)
    end

    test "validated entitlement receipts reject already-owned entitlement across providers" do
      user = AccountsFixtures.user_fixture()

      {_apple_product, apple_provider_product} =
        create_entitlement_provider_product("apple", "pass")

      {_google_product, google_provider_product} =
        create_entitlement_provider_product("google", "pass")

      assert {:ok, %{purchase: %Purchase{} = purchase, seen_before: false}} =
               Payments.validate_store_purchase(user, "apple", %{
                 "product_id" => apple_provider_product.external_id,
                 "transaction_id" => "apple_tx_pass_1",
                 "environment" => "test"
               })

      assert purchase.status == "completed"
      assert Payments.has_entitlement?(user.id, "battle_pass") == true

      assert {:error, :already_owned} =
               Payments.validate_store_purchase(user, "google", %{
                 "product_id" => google_provider_product.external_id,
                 "transaction_id" => "google_tx_pass_1",
                 "environment" => "test"
               })
    end

    test "a second purchase of one store transaction is a changeset, on SQLite too" do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_consumable_provider_product("apple", "coins_dup")
      attrs = %{"provider_transaction_id" => "apple_tx_dup"}

      assert {:ok, _purchase} = Payments.create_purchase(user, provider_product, attrs)

      # ecto_sqlite3 names the index after its columns, not its real name, so
      # with only the Postgres name declared this raised Ecto.ConstraintError.
      assert {:error, %Ecto.Changeset{} = changeset} =
               Payments.create_purchase(user, provider_product, attrs)

      assert errors_on(changeset).provider_transaction_id != []
    end

    test "a subscription's owner validates every renewal; another account none of them" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_consumable_provider_product("apple", "renewals")

      renewal = fn n ->
        %{
          "product_id" => provider_product.external_id,
          "transaction_id" => "apple_renewal_#{n}",
          "original_transaction_id" => "apple_original_renewals",
          "environment" => "test"
        }
      end

      # The third used to raise Ecto.MultipleResultsError: the original
      # transaction was looked up with `get_by`, and two purchases share it.
      for n <- 1..3 do
        assert {:ok, %{seen_before: false}} =
                 Payments.validate_store_purchase(user, "apple", renewal.(n))
      end

      assert %Purchase{provider_transaction_id: "apple_renewal_3"} =
               Payments.get_purchase_by_provider_original_transaction(
                 "apple",
                 "apple_original_renewals"
               )

      assert {:error, :receipt_already_used} =
               Payments.validate_store_purchase(other_user, "apple", renewal.(4))
    end

    test "revalidating a receipt whose purchase was left pending fulfils it" do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_entitlement_provider_product("apple", "stuck_pass")

      # What a fulfilment rolled back leaves: the purchase, still pending.
      {:ok, pending} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "apple_tx_stuck",
          "status" => "pending"
        })

      assert {:ok, %{purchase: purchase, seen_before: true}} =
               Payments.validate_store_purchase(user, "apple", %{
                 "product_id" => provider_product.external_id,
                 "transaction_id" => "apple_tx_stuck",
                 "environment" => "test"
               })

      assert purchase.id == pending.id
      assert purchase.status == "completed"
      assert Payments.has_entitlement?(user.id, "battle_pass")
    end
  end

  describe "revoke_purchase/2" do
    test "ends a purchase once: a second event for the same end changes nothing" do
      capture_payment_hooks()

      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_entitlement_provider_product("stripe", "refunded")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "cs_refunded_twice"
        })

      {:ok, purchase} = Payments.fulfill_purchase(purchase)
      purchase_id = purchase.id
      assert_receive {:payment_purchase_fulfilled, ^purchase_id, _}

      # `charge.refunded` and then `refund.updated` for the one refund.
      assert {:ok, %Purchase{status: "refunded"}} =
               Payments.revoke_purchase(purchase, %{"status" => "refunded", "reason" => "a"})

      assert_receive {:payment_purchase_revoked, ^purchase_id, _}

      assert {:ok, %Purchase{status: "refunded"} = again} =
               Payments.revoke_purchase(purchase, %{
                 "status" => "refunded",
                 "reason" => "b",
                 "payload" => %{"second_event" => true}
               })

      refute_receive {:payment_purchase_revoked, ^purchase_id, _}, 200
      assert again.metadata["revocation_reason"] == "a"
      assert again.raw_provider_payload["second_event"] == true
    end
  end

  defp create_consumable_provider_product(provider, external_id) do
    sku = unique_sku("coins")

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "100 Coins",
        "kind" => "consumable",
        "grant_config" => %{"hook_payload" => %{"coins" => 100}}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => external_id <> "_" <> to_string(System.unique_integer([:positive])),
        "currency" => "USD",
        "unit_amount" => 199
      })

    {product, provider_product}
  end

  defp create_entitlement_provider_product(provider, external_id) do
    sku = unique_sku("battle_pass")

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Battle Pass",
        "kind" => "entitlement",
        "grant_config" => %{"entitlement_key" => "battle_pass"}
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => external_id <> "_" <> to_string(System.unique_integer([:positive])),
        "currency" => "USD",
        "unit_amount" => 999
      })

    {product, provider_product}
  end

  defp create_subscription_provider_product(provider, external_id) do
    sku = unique_sku("premium")

    {:ok, product} =
      Payments.create_product(%{
        "sku" => sku,
        "title" => "Premium Monthly",
        "kind" => "subscription",
        "grant_config" => %{
          "entitlement_key" => "premium_subscription",
          "duration_seconds" => 2_592_000
        }
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => provider,
        "external_id" => external_id <> "_" <> to_string(System.unique_integer([:positive])),
        "currency" => "USD",
        "unit_amount" => 499
      })

    {product, provider_product}
  end

  defp capture_payment_hooks do
    :persistent_term.put({CapturePaymentHooks, :pid}, self())
    Application.put_env(:gamend_core, :hooks_module, CapturePaymentHooks)

    on_exit(fn ->
      :persistent_term.erase({CapturePaymentHooks, :pid})
    end)
  end

  defp use_default_payment_hooks do
    Application.put_env(:gamend_core, :hooks_module, Gamend.Hooks.Default)
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    fun.()
  rescue
    error ->
      if attempts == 1 do
        reraise error, __STACKTRACE__
      else
        Process.sleep(50)
        eventually(fun, attempts - 1)
      end
  end

  describe "grant_entitlement/3" do
    test "grants without a purchase, once per key, and says it ever existed" do
      user = AccountsFixtures.user_fixture()
      in_a_month = DateTime.add(DateTime.utc_now(:second), 30, :day)

      refute Payments.entitlement_ever?(user.id, "trial_key")

      assert {:ok, %Entitlement{} = e} =
               Payments.grant_entitlement(user.id, "trial_key",
                 expires_at: in_a_month,
                 metadata: %{"source" => "trial"}
               )

      assert e.status == "active"
      assert e.expires_at == in_a_month
      assert e.metadata["source"] == "trial"
      assert Payments.has_entitlement?(user.id, "trial_key")
      assert Payments.entitlement_ever?(user.id, "trial_key")
    end

    test "never shortens an active grant, and no end beats any end" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now(:second)
      long = DateTime.add(now, 365, :day)
      short = DateTime.add(now, 30, :day)

      {:ok, _} = Payments.grant_entitlement(user.id, "k", expires_at: long)
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: short)
      assert e.expires_at == long

      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: nil)
      assert is_nil(e.expires_at)

      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: short)
      assert is_nil(e.expires_at)
    end

    test "an expired grant is renewed from now, not extended from the past" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now(:second)

      {:ok, _} =
        Payments.grant_entitlement(user.id, "k2", expires_at: DateTime.add(now, -1, :day))

      refute Payments.has_entitlement?(user.id, "k2")

      {:ok, e} = Payments.grant_entitlement(user.id, "k2", expires_at: DateTime.add(now, 7, :day))
      assert Payments.has_entitlement?(user.id, "k2")
      assert DateTime.compare(e.expires_at, now) == :gt
    end
  end

  describe "a grant's notice" do
    defmodule NoticeHooks do
      def before_entitlement_notice(%{key: "quiet"}, _notice), do: {:error, :quiet}

      def before_entitlement_notice(%{key: "typo"}, notice),
        do: {:ok, Map.put(notice, "group", "no_such_group")}

      def before_entitlement_notice(_entitlement, notice),
        do: {:ok, Map.merge(notice, %{"group" => "quests", "title" => "From the hook"})}
    end

    @ends ~U[2030-01-15 10:00:00Z]

    defp notices(user), do: Gamend.Notifications.list_notifications(user.id)

    defp use_notice_hooks do
      previous = Application.get_env(:gamend_core, :host_hook_modules, [])
      Application.put_env(:gamend_core, :host_hook_modules, [NoticeHooks])
      on_exit(fn -> Application.put_env(:gamend_core, :host_hook_modules, previous) end)
    end

    test "nothing is said unless the grant asks" do
      user = AccountsFixtures.user_fixture()
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: @ends)
      {:ok, _extended} = Payments.extend_entitlement(e.id, 30)

      assert notices(user) == []
    end

    test "goes out in the payments group, naming the grant and its end" do
      user = AccountsFixtures.user_fixture()

      {:ok, _e} =
        Payments.grant_entitlement(user.id, "k",
          expires_at: @ends,
          metadata: %{"title" => "VIP pass"},
          notify: true
        )

      assert [row] = notices(user)
      assert row.title == "VIP pass is yours"
      assert row.content == "You have it until January 15, 2030."
      assert row.metadata["group"] == "payments"
      assert row.metadata["url"] == "/users/settings?tab=payments"
    end

    test "extending twice leaves one row, with the last end, and one email" do
      user = AccountsFixtures.user_fixture()
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: @ends, notify: true)

      {:ok, _} = Payments.extend_entitlement(e.id, 1, notify: true)
      {:ok, _} = Payments.extend_entitlement(e.id, 1, notify: true)

      assert [row] = notices(user)
      assert row.content == "You have it until January 17, 2030."
      assert [_one_email] = all_enqueued(queue: :mailers)
    end

    test "a user who turned the group's email off keeps the row and gets no email" do
      user = AccountsFixtures.user_fixture()
      {:ok, user} = Gamend.Notifications.Preferences.put(user, "payments", "email", false)

      {:ok, _e} = Payments.grant_entitlement(user.id, "k", expires_at: @ends, notify: true)

      assert [_row] = notices(user)
      assert all_enqueued(queue: :mailers) == []
    end

    test "the hook changes what is sent" do
      use_notice_hooks()
      user = AccountsFixtures.user_fixture()

      {:ok, _e} = Payments.grant_entitlement(user.id, "k", expires_at: @ends, notify: true)

      assert [row] = notices(user)
      assert row.title == "From the hook"
      assert row.metadata["group"] == "quests"
    end

    test "the hook can refuse, and a group that does not exist sends nothing" do
      use_notice_hooks()
      user = AccountsFixtures.user_fixture()

      assert {:ok, _e} =
               Payments.grant_entitlement(user.id, "quiet", expires_at: @ends, notify: true)

      assert {:ok, _e} =
               Payments.grant_entitlement(user.id, "typo", expires_at: @ends, notify: true)

      assert notices(user) == []
    end
  end

  describe "extend_entitlement/3" do
    test "adds after the end of one still running, and keeps who asked" do
      user = AccountsFixtures.user_fixture()
      ends = DateTime.add(DateTime.utc_now(:second), 10, :day)
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: ends)

      assert {:ok, extended} =
               Payments.extend_entitlement(e.id, 30, metadata: %{"extended_by" => "admin"})

      assert extended.id == e.id
      assert extended.expires_at == DateTime.add(ends, 30, :day)
      assert extended.starts_at == e.starts_at
      assert extended.metadata["extended_by"] == "admin"
    end

    test "counts from now once it has ended, and it is active again" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now(:second)
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: DateTime.add(now, -5, :day))
      refute Payments.has_entitlement?(user.id, "k")

      assert {:ok, extended} = Payments.extend_entitlement(e.id, 7)

      assert DateTime.compare(extended.expires_at, DateTime.add(now, 7, :day)) in [:eq, :gt]
      assert DateTime.compare(extended.expires_at, DateTime.add(now, 8, :day)) == :lt
      assert Payments.has_entitlement?(user.id, "k")
    end

    test "counts from now for a revoked one, not from the end it had" do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now(:second)
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: DateTime.add(now, 30, :day))
      {:ok, _revoked} = Payments.revoke_entitlement(user.id, "k")

      assert {:ok, extended} = Payments.extend_entitlement(e.id, 7)

      assert extended.status == "active"
      assert is_nil(extended.revoked_at)
      assert DateTime.compare(extended.expires_at, DateTime.add(now, 8, :day)) == :lt
    end

    test "refuses a row with no end, and one nobody holds" do
      user = AccountsFixtures.user_fixture()
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: nil)

      refute Payments.entitlement_extendable?(e)
      assert {:error, :no_end} = Payments.extend_entitlement(e.id, 7)

      assert {:error, :entitlement_not_found} =
               Payments.extend_entitlement(Ecto.UUID.generate(), 7)
    end

    test "refuses a row a purchase made, whose provider's sync would set it back" do
      user = AccountsFixtures.user_fixture()
      {_product, provider_product} = create_consumable_provider_product("stripe", "price_extend")

      {:ok, purchase} =
        Payments.create_purchase(user, provider_product, %{
          "provider_transaction_id" => "cs_test_extend"
        })

      ends = DateTime.add(DateTime.utc_now(:second), 30, :day)
      {:ok, e} = Payments.grant_entitlement(user.id, "k", expires_at: ends)
      e = e |> Ecto.Changeset.change(source_purchase_id: purchase.id) |> Repo.update!()

      refute Payments.entitlement_extendable?(e)
      assert {:error, :purchased} = Payments.extend_entitlement(e.id, 7)
      assert Repo.get!(Entitlement, e.id).expires_at == ends
    end
  end

  describe "revoke_entitlement/3" do
    test "ends a grant now, keeping the row and what it recorded" do
      user = AccountsFixtures.user_fixture()
      in_a_month = DateTime.add(DateTime.utc_now(:second), 30, :day)

      {:ok, _} =
        Payments.grant_entitlement(user.id, "trial_key",
          expires_at: in_a_month,
          metadata: %{"source" => "trial"}
        )

      assert {:ok, %Entitlement{status: "revoked", revoked_at: %DateTime{}} = e} =
               Payments.revoke_entitlement(user.id, "trial_key",
                 metadata: %{"revocation_reason" => "upgraded"}
               )

      assert e.metadata == %{"source" => "trial", "revocation_reason" => "upgraded"}
      refute Payments.has_entitlement?(user.id, "trial_key")
      assert Payments.entitlement_ever?(user.id, "trial_key")

      # A grant after it makes it active again.
      {:ok, _} = Payments.grant_entitlement(user.id, "trial_key", expires_at: in_a_month)
      assert Payments.has_entitlement?(user.id, "trial_key")
    end

    test "answers what it cannot end" do
      user = AccountsFixtures.user_fixture()

      assert {:error, :entitlement_not_found} =
               Payments.revoke_entitlement(user.id, "never_granted")
    end
  end

  defp unique_sku(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
