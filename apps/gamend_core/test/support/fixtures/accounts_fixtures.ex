defmodule Gamend.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Gamend.Accounts` context.
  """

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    # Convert attrs to map if it's a keyword list
    attrs = Map.new(attrs)
    # Only set default email if no email is provided
    defaults =
      if Map.has_key?(attrs, "email") or Map.has_key?(attrs, :email) do
        %{}
      else
        %{"email" => unique_user_email()}
      end

    Map.merge(defaults, attrs)
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  # A confirmed account, confirmed in place. Going through the magic link
  # (an email, a login, its hooks and its quest event) cost ~3x a bare
  # registration in every test that makes a user; a test about logging in
  # logs in itself.
  def user_fixture(attrs \\ %{}) do
    attrs
    |> unconfirmed_user_fixture()
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  @doc """
  Make two users friends.

  Group and party invites both require an existing connection, so any test that
  invites someone has to establish one first — otherwise it is asserting against
  `{:error, :not_connected}` rather than against the behaviour it means to test.
  """
  def befriend(%Accounts.User{} = a, %Accounts.User{} = b) do
    {:ok, friendship} = Gamend.Friends.create_request(a.id, b.id)
    {:ok, _} = Gamend.Friends.accept_friend_request(friendship.id, b)
    :ok
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
