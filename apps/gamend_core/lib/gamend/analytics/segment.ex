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

  A segment can carry one TRAIT too, `{segment, {field, value}}`
  (`with_trait/2`): the accounts with an event row whose field holds that
  value, any day (`{"device", "phone"}`: an account seen on a phone). The
  fields worth one are the host's (`Gamend.Analytics.Catalog.overview/0`'s
  `traits`); an account seen on a phone and on a laptop is in both.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Analytics.Event

  require Gamend.Analytics.SegmentName, as: SegmentName

  @type base :: :all | :registered | :guest
  @type trait :: {String.t(), String.t()}
  @type t :: base() | {base(), trait()}

  @segments [:all, :registered, :guest]

  @doc "Every segment, `:all` first."
  @spec all() :: [base()]
  def all, do: @segments

  @doc "A segment from a request parameter (`\"guest\"`); anything else is `:all`."
  @spec parse(term()) :: base()
  def parse(SegmentName.registered()), do: :registered
  def parse(SegmentName.guest()), do: :guest
  def parse(segment) when segment in @segments, do: segment
  def parse(_param), do: :all

  @doc """
  A trait from a request parameter, `"field:value"` (`"device:phone"`), or
  nil: a field of letters, digits and `_` (32 at most) and a value of 64 at
  most, so nothing else reaches a query.
  """
  @spec parse_trait(term()) :: trait() | nil
  def parse_trait(param) when is_binary(param) do
    with [field, value] <- String.split(param, ":", parts: 2),
         true <- Regex.match?(~r/\A[a-z0-9_]{1,32}\z/, field),
         true <- value != "" and String.length(value) <= 64 do
      {field, value}
    else
      _ -> nil
    end
  end

  def parse_trait(_param), do: nil

  @doc "A trait as its parameter (`parse_trait/1`'s); nil for none."
  @spec trait_param(trait() | nil) :: String.t() | nil
  def trait_param({field, value}), do: field <> ":" <> value
  def trait_param(nil), do: nil

  @doc "`segment` narrowed to the accounts with `trait`; nil leaves it as it is."
  @spec with_trait(base(), trait() | nil) :: t()
  def with_trait(segment, nil), do: segment
  def with_trait(segment, {field, value}) when segment in @segments, do: {segment, {field, value}}

  @doc "How a page names it."
  @spec label(base()) :: String.t()
  def label(:all), do: "All accounts"
  def label(:registered), do: "Registered"
  def label(:guest), do: "Guests"

  @doc """
  Restricts `query` to one segment: a query on a table with a `user_id` is
  joined to `users` (as `:user`); a query that already has a `:user` binding
  (`users` itself, `as: :user`) is filtered on it.
  """
  @spec restrict(Ecto.Queryable.t(), t()) :: Ecto.Query.t()
  def restrict(query, {segment, {field, value}}) do
    query = query |> restrict(segment) |> Ecto.Queryable.to_query()

    query =
      if has_named_binding?(query, :user),
        do: query,
        else: join(query, :inner, [x], u in User, on: u.id == x.user_id, as: :user)

    # `->>` with a CAST: the same SQL on Postgres (jsonb) and SQLite (JSON
    # text), as `Gamend.Analytics.Explore` reads a field.
    with_trait =
      from(e in Event,
        where: not is_nil(e.user_id),
        where: fragment("? ->> CAST(? AS TEXT)", e.dims, ^field) == ^value,
        distinct: true,
        select: e.user_id
      )

    where(query, [user: u], u.id in subquery(with_trait))
  end

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
