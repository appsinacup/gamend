defmodule Gamend.Accounts.Stats do
  @moduledoc """
  Counts over the user table for the admin dashboard and the public stats page.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache
  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Repo

  # Upper bound on cross-node staleness for cached user structs: explicit
  # invalidations propagate immediately via `Gamend.Cache.invalidate/1`,
  # and this TTL caps staleness if an invalidation broadcast is ever missed.

  @doc """
  Returns the total number of users.
  """
  @spec count_users() :: non_neg_integer()
  @decorate cacheable(key: {:accounts, :users_count}, opts: [ttl: Gamend.Cache.ttl()])
  def count_users, do: Repo.aggregate(User, :count, :id)

  @doc """
  How many accounts hold the admin flag.

  Used to refuse the write that would take that number to zero: nothing else can
  grant `is_admin`, so an installation that reaches zero admins cannot be
  administered again.
  """
  @spec count_admins() :: non_neg_integer()
  def count_admins do
    Repo.one(from(u in User, where: u.is_admin == true, select: count(u.id))) || 0
  end

  @doc """
  Count users with non-empty provider id for a given provider field (e.g. :google_id)
  """
  @spec count_users_with_provider(atom()) :: non_neg_integer()
  def count_users_with_provider(provider_field) when is_atom(provider_field) do
    count_users_with_provider_cached(provider_field)
  end

  @decorate cacheable(
              key:
                {:accounts, :stats, Accounts.users_stats_cache_version(), :users_with_provider,
                 provider_field},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp count_users_with_provider_cached(provider_field) do
    Repo.one(
      from u in User,
        where: not is_nil(field(u, ^provider_field)) and field(u, ^provider_field) != "",
        select: count(u.id)
    ) || 0
  end

  @doc """
  Count users with a password set (hashed_password not nil/empty).
  """
  @spec count_users_with_password() :: non_neg_integer()
  def count_users_with_password do
    count_users_with_password_cached()
  end

  @decorate cacheable(
              key:
                {:accounts, :stats, Accounts.users_stats_cache_version(), :users_with_password},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp count_users_with_password_cached do
    Repo.one(
      from u in User,
        where: not is_nil(u.hashed_password) and u.hashed_password != "",
        select: count(u.id)
    ) || 0
  end

  @doc """
  Ids of every admin user.

  Used to fan a moderation alert out to whoever can act on it. Not cached: the
  callers are rare (a chat report arriving), and a stale list would silently
  skip a newly promoted moderator.
  """
  @spec list_admin_ids() :: [Ecto.UUID.t()]
  def list_admin_ids do
    Repo.all(from u in User, where: u.is_admin == true, select: u.id)
  end

  @doc """
  Count users currently marked as online.
  """
  @spec count_users_online() :: non_neg_integer()
  def count_users_online do
    Repo.one(from u in User, where: u.is_online == true, select: count(u.id)) || 0
  end

  @doc """
  Aggregate player counts for the public stats endpoint.

  Every field is derived, never a counter: a counter would put a write on the
  login path (SQLite has one writer) and would drift from the bulk updates in
  `touch_users/1` and `StalePresenceSweeper`. `players_online` rides the
  partial index over online rows, so it scans the smallest set; the unfiltered
  `players_total` cannot use an index at all, which is what the cache is for.
  """
  @spec player_stats() :: %{
          players_online: non_neg_integer(),
          players_total: non_neg_integer(),
          players_offline: non_neg_integer(),
          players_in_lobbies: non_neg_integer(),
          players_in_parties: non_neg_integer()
        }
  def player_stats do
    Gamend.Cache.cached({:accounts, :player_stats}, [ttl: Gamend.Cache.ttl()], fn ->
      total = count_users()
      online = count_users_online()

      %{
        players_online: online,
        players_total: total,
        players_offline: max(total - online, 0),
        players_in_lobbies: count_users_in_lobbies(),
        players_in_parties: count_users_in_parties()
      }
    end)
  end

  @doc "Count users currently seated in a lobby (`users.lobby_id`, indexed)."
  @spec count_users_in_lobbies() :: non_neg_integer()
  def count_users_in_lobbies do
    Repo.one(from u in User, where: not is_nil(u.lobby_id), select: count(u.id)) || 0
  end

  @doc "Count users currently in a party (`users.party_id`, indexed)."
  @spec count_users_in_parties() :: non_neg_integer()
  def count_users_in_parties do
    Repo.one(from u in User, where: not is_nil(u.party_id), select: count(u.id)) || 0
  end

  @doc """
  Count users who are not yet activated (is_activated == false).
  """
  @spec count_unactivated_users() :: non_neg_integer()
  def count_unactivated_users do
    Repo.one(from u in User, where: u.is_activated == false, select: count(u.id)) || 0
  end
end
