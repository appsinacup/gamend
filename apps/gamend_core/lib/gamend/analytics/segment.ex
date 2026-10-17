defmodule Gamend.Analytics.Segment do
  @moduledoc """
  The ways the people numbers split: `:all`, `:registered` (an account with
  an identity: an email, a provider) and `:guest` (an account backed by
  nothing but a device or a browser, `Gamend.Accounts.User.anonymous?/1`).
  A visitor with no account is in none of them: the daily counters count
  them, no row does.

  The split is by what the account is NOW, so a guest who registers later
  reads as registered on the days before too: a guest's numbers are the
  guests who stayed guests.
  """

  import Ecto.Query

  alias Gamend.Accounts.User

  @type t :: :all | :registered | :guest

  @segments [:all, :registered, :guest]

  @doc "Every segment, `:all` first."
  @spec all() :: [t()]
  def all, do: @segments

  @doc "A segment from a request parameter (`\"guest\"`); anything else is `:all`."
  @spec parse(term()) :: t()
  def parse("registered"), do: :registered
  def parse("guest"), do: :guest
  def parse(segment) when segment in @segments, do: segment
  def parse(_param), do: :all

  @doc "How a page names it."
  @spec label(t()) :: String.t()
  def label(:all), do: "All accounts"
  def label(:registered), do: "Registered"
  def label(:guest), do: "Guests"

  @doc """
  Restricts `query` to one segment: a query on a table with a `user_id` is
  joined to `users` (as `:user`); a query that already has a `:user` binding
  (`users` itself, `as: :user`) is filtered on it.
  """
  @spec restrict(Ecto.Queryable.t(), t()) :: Ecto.Query.t()
  def restrict(query, :all), do: query

  def restrict(query, segment) when segment in [:registered, :guest] do
    query = Ecto.Queryable.to_query(query)

    query =
      if has_named_binding?(query, :user),
        do: query,
        else: join(query, :inner, [x], u in User, on: u.id == x.user_id, as: :user)

    where(query, ^condition(segment))
  end

  @doc "The `where` for one segment over a `:user` binding."
  @spec condition(:registered | :guest) :: Ecto.Query.dynamic_expr()
  def condition(:guest) do
    Enum.reduce(User.identity_fields(), dynamic(true), fn field, acc ->
      dynamic([user: u], ^acc and is_nil(field(u, ^field)))
    end)
  end

  def condition(:registered), do: dynamic(not (^condition(:guest)))
end
