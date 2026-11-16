defmodule Gamend.HooksTest do
  # This test touches global Application environment (hooks module) and
  # must not run concurrently with other tests that depend on application
  # configuration values. Run serially to avoid races where a temporary
  # test hook leaks into other tests.
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Accounts.UserToken
  alias Gamend.Repo
  import Gamend.AccountsFixtures

  setup do
    orig = Application.get_env(:gamend_core, :hooks_module)
    :persistent_term.put({__MODULE__, :test_pid}, self())

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :test_pid})
      Application.put_env(:gamend_core, :hooks_module, orig)
    end)

    :ok
  end

  defmodule TestHooksRegister do
    use Gamend.TestSupport.NoopHooks

    # Each hook marks the user's metadata, so a test sees the hook could write,
    # then tells the test it ran: they run off the caller's process.
    @impl true
    def after_user_register(user), do: mark(user, "registered_hook")

    @impl true
    def after_user_logged_in(user), do: mark(user, "hooked")

    @impl true
    def after_user_online(user), do: mark(user, "online_hook")

    @impl true
    def after_user_offline(user), do: mark(user, "offline_hook")

    defp mark(user, key) do
      meta = Map.put(user.metadata || %{}, key, true)
      updated = Repo.update!(Ecto.Changeset.change(user, metadata: meta))

      if pid = :persistent_term.get({Gamend.HooksTest, :test_pid}, nil),
        do: send(pid, {:hook_ran, key})

      updated
    end
  end

  test "after_user_register hook runs and can modify the created user" do
    Application.put_env(:gamend_core, :hooks_module, TestHooksRegister)

    {:ok, user} = Accounts.register_user(%{email: "a@example.com"})

    assert_receive {:hook_ran, "registered_hook"}, 1_000

    reloaded = Accounts.get_user!(user.id)
    assert Map.get(reloaded.metadata || %{}, "registered_hook") == true
  end

  test "linking a provider retires the account's device credential" do
    device_id = "dev-#{System.unique_integer([:positive])}"
    user = unconfirmed_user_fixture()
    {:ok, user} = Accounts.link_device_id(user, device_id)

    assert is_binary(user.device_id)

    {:ok, user} =
      Accounts.link_account(
        user,
        %{discord_id: "d999"},
        :discord_id,
        &User.discord_oauth_changeset/2
      )

    assert user.discord_id == "d999"

    # The provider is linked, and device auth stops being one of this account's
    # sign-in methods. A device id is a standing credential nobody has to prove
    # they still hold: it is unaffected by `token_version` and may predate the
    # link entirely. Re-attach deliberately via `link_device_id/2` if wanted.
    assert is_nil(user.device_id)
  end

  test "after_user_logged_in hook runs on successful magic-link login" do
    Application.put_env(:gamend_core, :hooks_module, TestHooksRegister)

    user = unconfirmed_user_fixture()
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)

    assert {:ok, {_, _}} = Accounts.login_user_by_magic_link(encoded_token)

    assert_receive {:hook_ran, "hooked"}, 1_000

    reloaded = Accounts.get_user!(user.id)
    assert Map.get(reloaded.metadata || %{}, "hooked") == true
  end

  test "after_user_online hook fires when user comes online" do
    Application.put_env(:gamend_core, :hooks_module, TestHooksRegister)

    user = unconfirmed_user_fixture()
    {:ok, _online_user} = Accounts.set_user_online(user.id)

    assert_receive {:hook_ran, "online_hook"}, 1_000

    reloaded = Accounts.get_user!(user.id)
    assert reloaded.is_online == true
    assert Map.get(reloaded.metadata || %{}, "online_hook") == true
  end

  test "after_user_offline hook fires when user goes offline" do
    Application.put_env(:gamend_core, :hooks_module, TestHooksRegister)

    user = unconfirmed_user_fixture()
    {:ok, _online} = Accounts.set_user_online(user.id)
    {:ok, _offline} = Accounts.set_user_offline(user.id)

    assert_receive {:hook_ran, "offline_hook"}, 1_000

    reloaded = Accounts.get_user!(user.id)
    assert reloaded.is_online == false
    assert Map.get(reloaded.metadata || %{}, "offline_hook") == true
  end

  describe "scheduled callbacks protection" do
    defmodule ScheduleTestHook do
      use Gamend.TestSupport.NoopHooks

      alias Gamend.Schedule

      @impl true
      def after_startup do
        # Register a scheduled callback
        Schedule.every_minutes(60, :my_scheduled_job)
        :ok
      end

      @impl true
      def before_stop, do: :ok

      # This is a public scheduled callback - protected from RPC
      def my_scheduled_job(_context), do: :ok
    end

    alias Gamend.Hooks
    alias Gamend.Schedule

    test "scheduled callbacks are blocked from RPC call/3" do
      Application.put_env(:gamend_core, :hooks_module, ScheduleTestHook)

      # Trigger after_startup to register the scheduled job
      Hooks.internal_call(:after_startup, [])

      # The scheduled callback should be registered
      assert MapSet.member?(Schedule.registered_callbacks(), :my_scheduled_job)

      # Trying to call it via the public RPC API should fail
      assert {:error, :disallowed} = Hooks.call(:my_scheduled_job, [%{}])

      # Clean up
      Schedule.cancel(:my_scheduled_job)
    end

    test "cancelling a job removes it from protected list" do
      Application.put_env(:gamend_core, :hooks_module, ScheduleTestHook)

      # Register job
      Schedule.every_minutes(30, :temp_job)
      assert MapSet.member?(Schedule.registered_callbacks(), :temp_job)

      # Cancel it
      Schedule.cancel(:temp_job)
      refute MapSet.member?(Schedule.registered_callbacks(), :temp_job)
    end
  end

  defmodule HostPipelineHooks do
    use Gamend.TestSupport.NoopHooks

    def before_build(attrs) do
      case attrs do
        %{"block" => true} -> {:error, :blocked_by_plugin}
        _ -> {:ok, Map.put(attrs, "touched", true)}
      end
    end
  end

  describe "register_pipeline_hook/1" do
    setup do
      Application.put_env(:gamend_core, :hooks_module, HostPipelineHooks)
      on_exit(fn -> Gamend.Hooks.unregister_pipeline_hook(:before_build) end)
      :ok
    end

    # The predicate is what routes a name to the chaining path instead of the
    # fan-out one, and the admin runtime page reads it too.
    test "a host hook is not a pipeline hook until it is registered" do
      refute Gamend.Hooks.pipeline_hook?(:before_build, 1)

      Gamend.Hooks.register_pipeline_hook(:before_build)

      assert Gamend.Hooks.pipeline_hook?(:before_build, 1)
    end

    test "unregister_pipeline_hook/1 puts it back" do
      Gamend.Hooks.register_pipeline_hook(:before_build)
      Gamend.Hooks.unregister_pipeline_hook(:before_build)

      refute Gamend.Hooks.pipeline_hook?(:before_build, 1)
    end

    # Pipeline hooks normalize map arguments to string keys before the chain
    # runs, so a plugin never has to handle both key styles.
    test "a registered host hook receives string keys" do
      Gamend.Hooks.register_pipeline_hook(:before_build)

      assert {:ok, %{"touched" => true, "a" => 1}} =
               Gamend.Hooks.internal_call(:before_build, [%{a: 1}])
    end

    test "a registered host hook can block" do
      Gamend.Hooks.register_pipeline_hook(:before_build)

      assert {:error, :blocked_by_plugin} =
               Gamend.Hooks.internal_call(:before_build, [%{"block" => true}])
    end

    test "registering twice does not duplicate the name" do
      Gamend.Hooks.register_pipeline_hook(:before_build)
      Gamend.Hooks.register_pipeline_hook(:before_build)

      assert Enum.count(Gamend.Hooks.pipeline_hooks(), &(&1 == :before_build)) == 1
    end

    test "core's own pipeline hooks still work with none registered" do
      assert Gamend.Hooks.pipeline_hooks() == []

      assert {:ok, %{}} = Gamend.Hooks.internal_call(:before_lobby_create, [%{}])
    end
  end
end
