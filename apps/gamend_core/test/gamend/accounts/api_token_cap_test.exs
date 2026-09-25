defmodule Gamend.Accounts.ApiTokenCapTest do
  # `auth.api_token_max_days` is global Application config.
  use Gamend.DataCase, async: false

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.ApiToken
  alias Gamend.Accounts.ApiTokens
  alias Gamend.AccountsFixtures
  alias Gamend.SettingsHelpers

  setup do
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, :api_token_max_days) end)
    %{user: AccountsFixtures.user_fixture()}
  end

  test "uncapped, a token may never expire" do
    assert ApiToken.expiry_choices() == [30, 90, 365, nil]
  end

  test "a cap trims the choices to it and takes away never", %{user: user} do
    SettingsHelpers.put(:gamend_core, Accounts, :api_token_max_days, 180)
    assert ApiToken.expiry_choices() == [30, 90, 180]

    assert {:ok, _, row} = ApiTokens.create(user, %{"name" => "ci", "expires_in_days" => 180})
    assert DateTime.diff(row.expires_at, DateTime.utc_now(), :day) in 179..180

    assert {:error, changeset} =
             ApiTokens.create(user, %{"name" => "forever", "expires_in_days" => nil})

    assert "can't be blank" in errors_on(changeset).expires_in_days

    assert {:error, changeset} =
             ApiTokens.create(user, %{"name" => "long", "expires_in_days" => 365})

    assert errors_on(changeset).expires_in_days != []
  end

  test "a cap ends tokens made before it, counted from their creation", %{user: user} do
    {:ok, token, row} = ApiTokens.create(user, %{"name" => "forever", "expires_in_days" => nil})
    made = DateTime.add(DateTime.utc_now(:second), -40, :day)
    Repo.update_all(from(t in ApiToken, where: t.id == ^row.id), set: [inserted_at: made])

    assert {:ok, _, _} = ApiTokens.verify(token)

    SettingsHelpers.put(:gamend_core, Accounts, :api_token_max_days, 30)
    row = Repo.get!(ApiToken, row.id)

    assert ApiTokens.expires_at(row) == DateTime.add(made, 30, :day)
    assert ApiTokens.expired?(row)
    assert ApiTokens.verify(token) == :error
    assert row.id in Repo.all(from(t in ApiTokens.dead_query(), select: t.id))
  end
end
