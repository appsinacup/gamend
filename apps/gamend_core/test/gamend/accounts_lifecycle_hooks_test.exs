defmodule Gamend.AccountsLifecycleHooksTest.Host do
  @moduledoc false

  alias Gamend.Accounts.User
  alias Gamend.Repo

  def before_user_delete(user) do
    tell({:before_delete, user.id, Repo.get(User, user.id) != nil})
    if :persistent_term.get({__MODULE__, :raise}, false), do: raise("hook failed")
    {:error, :ignored}
  end

  def after_user_updated(user), do: tell({:updated, user.email})

  defp tell(message), do: send(:persistent_term.get({__MODULE__, :test}), message)
end

defmodule Gamend.AccountsLifecycleHooksTest do
  @moduledoc """
  The account events a host hears: `before_user_delete/1` while the account can
  still be read, and `after_user_updated/1` for a new email.
  """
  use Gamend.DataCase

  import ExUnit.CaptureLog
  import Gamend.AccountsFixtures

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsLifecycleHooksTest.Host

  setup do
    original = Application.get_env(:gamend_core, :host_hook_modules)
    Application.put_env(:gamend_core, :host_hook_modules, [Host])
    :persistent_term.put({Host, :test}, self())

    on_exit(fn ->
      :persistent_term.erase({Host, :test})
      :persistent_term.erase({Host, :raise})

      if original,
        do: Application.put_env(:gamend_core, :host_hook_modules, original),
        else: Application.delete_env(:gamend_core, :host_hook_modules)
    end)
  end

  describe "before_user_delete/1" do
    test "runs while the account exists, and its answer does not stop the delete" do
      user = user_fixture()

      assert {:ok, _user} = Accounts.delete_user(user)

      assert_received {:before_delete, id, true}
      assert id == user.id
      refute Repo.get(User, user.id)
    end

    test "that raises stops nothing" do
      user = user_fixture()
      :persistent_term.put({Host, :raise}, true)

      capture_log(fn -> assert {:ok, _user} = Accounts.delete_user(user) end)

      refute Repo.get(User, user.id)
    end
  end

  describe "update_user_email/2" do
    test "tells after_user_updated/1 of the new address" do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)

      assert_receive {:updated, ^email}, 1_000
    end
  end
end
