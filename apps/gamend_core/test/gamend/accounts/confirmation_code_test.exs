defmodule Gamend.Accounts.ConfirmationCodeTest do
  @moduledoc """
  Confirming a registration: the emailed code (`Accounts.confirm_user_by_code/3`),
  which sets the password, and the emailed link (`confirm_user_by_token/1`),
  which never keeps one set before the inbox was proved.
  """
  # Lockout settings are global Application config.
  use Gamend.DataCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  import Gamend.AccountsFixtures

  alias Gamend.Accounts
  alias Gamend.Accounts.{ConfirmationMailer, LoginLockouts, PasswordHash, User, UserToken}
  alias Gamend.SettingsHelpers

  @password "a brand new password"

  defmodule CaptureNotifier do
    def deliver_confirmation_instructions(_user, url, code) do
      send(self(), {:confirmation, url, code})
      {:ok, :sent}
    end
  end

  setup do
    # Not the first account, which a game client's registration also emails,
    # but which would be the admin.
    _existing = user_fixture()
    email = unique_user_email()

    {:ok, user} =
      Accounts.register_unconfirmed_user_and_deliver(
        %{"email" => email},
        &"http://x/#{&1}",
        CaptureNotifier
      )

    {token, code} = send_email(user)
    %{user: user, email: email, token: token, code: code}
  end

  # Runs the account's newest confirmation job; answers what its email held.
  defp send_email(user) do
    job =
      [worker: ConfirmationMailer, args: %{"user_id" => user.id}]
      |> all_enqueued()
      |> List.first()

    assert :ok = perform_job(ConfirmationMailer, job.args)
    assert_received {:confirmation, "http://x/" <> token, code}
    {token, code}
  end

  defp lockout_attempts(attempts) do
    SettingsHelpers.put(:gamend_core, Accounts, :lockout_attempts, attempts)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, :lockout_attempts) end)
  end

  describe "confirm_user_by_code/3" do
    test "confirms, sets the password and spends the link", ctx do
      assert {:ok, {%User{} = user, _expired}} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)

      assert user.confirmed_at
      assert {:ok, _} = Accounts.authenticate_by_password(ctx.email, @password)
      assert {:error, :not_found} = Accounts.confirm_user_by_token(ctx.token)

      assert {:error, :invalid_code} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)
    end

    test "revokes the tokens the account held before", ctx do
      version = Repo.get!(User, ctx.user.id).token_version

      assert {:ok, {user, _expired}} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)

      assert user.token_version == version + 1
    end

    test "takes the code as it is read off an email", ctx do
      {first, last} = String.split_at(ctx.code, 3)

      assert {:ok, _} =
               Accounts.confirm_user_by_code(ctx.email, " #{first} - #{last} ", @password)
    end

    test "a refused password costs no attempt and keeps the code", ctx do
      lockout_attempts(1)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, "short")

      assert %{password: [_ | _]} = errors_on(changeset)
      assert {:ok, _} = Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)
    end

    test "a wrong code counts toward the lockout, and the one that locks voids the code", ctx do
      lockout_attempts(2)

      assert {:error, :invalid_code} =
               Accounts.confirm_user_by_code(ctx.email, wrong(ctx.code), @password)

      assert {:error, {:locked, _}} =
               Accounts.confirm_user_by_code(ctx.email, wrong(ctx.code), @password)

      assert {:error, {:locked, _}} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)

      LoginLockouts.clear(ctx.email)

      assert {:error, :invalid_code} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)

      # The link still works.
      assert {:ok, %User{confirmed_at: %DateTime{}}} = Accounts.confirm_user_by_token(ctx.token)
    end

    test "an address with no account waiting answers the same", ctx do
      assert {:error, :invalid_code} =
               Accounts.confirm_user_by_code(unique_user_email(), ctx.code, @password)

      assert {:ok, _} = Accounts.confirm_user_by_token(ctx.token)

      assert {:error, :invalid_code} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)
    end

    test "an expired code is refused", ctx do
      days = UserToken.confirm_validity_in_days()

      Repo.update_all(
        from(t in UserToken, where: t.user_id == ^ctx.user.id and t.context == "confirm_code"),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -days - 1, :day)]
      )

      assert {:error, :invalid_code} =
               Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)

      assert Repo.exists?(
               where(UserToken.expired_query(), user_id: ^ctx.user.id, context: "confirm_code")
             )
    end
  end

  describe "resend_confirmation/3" do
    test "sends a new code, and only the newest one works", ctx do
      # A minute after the first email, so it is not dropped as a repeat.
      Repo.update_all(Oban.Job,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :minute)]
      )

      assert :ok = Accounts.resend_confirmation(ctx.email, &"http://x/#{&1}", CaptureNotifier)
      {_token, code} = send_email(ctx.user)

      if code != ctx.code do
        assert {:error, :invalid_code} =
                 Accounts.confirm_user_by_code(ctx.email, ctx.code, @password)
      end

      assert {:ok, _} = Accounts.confirm_user_by_code(ctx.email, code, @password)
    end

    test "queues at most one email a minute", ctx do
      assert :ok = Accounts.resend_confirmation(ctx.email, &"http://x/#{&1}", CaptureNotifier)
      assert [_registration_email] = all_enqueued(worker: ConfirmationMailer)
    end

    test "answers :ok and sends nothing for an address with nothing to confirm", ctx do
      Repo.delete_all(Oban.Job)
      assert :ok = Accounts.resend_confirmation(unique_user_email(), & &1, CaptureNotifier)

      assert {:ok, _} = Accounts.confirm_user_by_token(ctx.token)
      assert :ok = Accounts.resend_confirmation(ctx.email, & &1, CaptureNotifier)

      assert [] = all_enqueued(worker: ConfirmationMailer)
    end
  end

  describe "the emailed link" do
    test "opening its page changes nothing", ctx do
      assert %User{id: id, confirmed_at: nil} = Accounts.get_user_by_confirm_token(ctx.token)
      assert id == ctx.user.id
      assert Accounts.get_user_by_confirm_token(ctx.token)
    end

    test "removes a password set before the address was confirmed", ctx do
      # How an account registered when the API still took a password looks.
      ctx.user
      |> Ecto.Changeset.change(hashed_password: PasswordHash.hash(@password))
      |> Repo.update!()

      assert {:ok, %User{confirmed_at: %DateTime{}, hashed_password: nil}} =
               Accounts.confirm_user_by_token(ctx.token)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(ctx.email, @password)
    end

    test "spends the code", ctx do
      assert {:ok, _} = Accounts.confirm_user_by_token(ctx.token)

      refute Repo.exists?(
               from(t in UserToken,
                 where: t.user_id == ^ctx.user.id and t.context == "confirm_code"
               )
             )
    end
  end

  defp wrong(code), do: if(code == "111111", do: "222222", else: "111111")
end
