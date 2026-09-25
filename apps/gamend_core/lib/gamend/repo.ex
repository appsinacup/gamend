defmodule Gamend.Repo do
  # The adapter must be present at compile time for Ecto.Repo's supervisor
  # initialization. Read the adapter from the application configuration
  # (config/config.exs and environment-specific files). This keeps the
  # logic out of the module and avoids reading System.env directly here.

  # Use compile-time access so the adapter selection is fixed at compile time
  # and picked up from the config files.
  #
  # Scoped to the :adapter sub-key rather than the whole Gamend.Repo entry.
  # `Application.compile_env/3` records what it reads and a release re-checks it
  # at boot, aborting when the runtime value differs — and the whole entry
  # always differs, because runtime.exs is what fills in :database, :pool_size
  # and the rest. Only the adapter has to be fixed at compile time, so only the
  # adapter is what we depend on.
  @adapter Application.compile_env(:gamend_core, [__MODULE__, :adapter], Ecto.Adapters.SQLite3)

  use Ecto.Repo,
    otp_app: :gamend_core,
    adapter: @adapter

  # All tables use UUID (v7) primary/foreign keys — see Gamend.UUIDv7.
  # Set here (not only in config files) so host repos that configure the Repo
  # themselves still get binary_id migrations.
  @impl true
  def init(_type, config) do
    {:ok,
     config
     |> Keyword.put_new(:migration_primary_key, name: :id, type: :binary_id)
     |> Keyword.put_new(:migration_foreign_key, type: :binary_id)}
  end

  @doc """
  Run `fun` in a transaction whose commit is on disk before it returns.

  `db.postgres_synchronous_commit` is an app-wide durability choice, and `off`
  is a reasonable one for game data: an OS crash loses a few hundred
  milliseconds of commits, nothing is corrupted, and a player re-earns a
  little progress. That trade is wrong for money — a purchase the provider has
  already charged for must not be the thing that disappears.

  `SET LOCAL` raises `synchronous_commit` back to `on` for this transaction
  only, so payments stay durable whatever the global setting is, and every
  other write keeps the faster commit. It costs one fsync per payment, which
  is not a path that needs throughput.

  A no-op on SQLite: durability there is `db.sqlite_synchronous`, a
  connection-wide pragma with no per-transaction override.
  """
  @spec durable_transaction((-> result), keyword()) :: {:ok, result} | {:error, term()}
        when result: term()
  def durable_transaction(fun, opts \\ []) when is_function(fun, 0) do
    Gamend.AfterCommit.transaction(
      fn ->
        if postgres?() do
          query!("SET LOCAL synchronous_commit = on", [])
        end

        fun.()
      end,
      opts
    )
  end

  # Built at runtime rather than compared against the compile-time constant:
  # when SQLite is the compiled adapter, Elixir's type checker folds a literal
  # comparison to `false` and warns on the branch below it.
  defp postgres? do
    __adapter__() == Module.concat([Ecto, Adapters, Postgres])
  end

  @doc """
  Runs `fun`, answering `{:error, reason}` when it violates a foreign key --
  however the adapter reports it.

  The contexts check the referenced row exists first
  (`Gamend.Accounts.user_exists?/1`), but the row can still be deleted between
  that check and the write. This closes that window: the race answers like the
  check would have, instead of a 500 or a changeset.

  The adapters report the violation differently, which is why both forms are
  handled here:

    * SQLite, the default, does not say *which* constraint an INSERT violated,
      so `Ecto.Changeset.foreign_key_constraint/2` cannot match and Ecto raises
      `Ecto.ConstraintError`.
    * Postgres names the constraint, so the changeset declaration matches and
      `fun` returns `{:error, changeset}` -- or `{:error, {tag, changeset}}`
      from a context that tags its failures -- with a `constraint: :foreign`
      error on the key.

  Handling only the first answered `:user_not_found` on SQLite and a
  validation changeset on Postgres for the same race. Any other constraint
  error is re-raised, and any other error result is returned as it was.
  """
  @spec rescue_foreign_key(term(), (-> result)) :: result | {:error, term()} when result: term()
  def rescue_foreign_key(reason, fun) when is_function(fun, 0) do
    case fun.() do
      {:error, error} = result ->
        if foreign_key_error?(error), do: {:error, reason}, else: result

      result ->
        result
    end
  rescue
    error in Ecto.ConstraintError ->
      if error.type == :foreign_key,
        do: {:error, reason},
        else: reraise(error, __STACKTRACE__)
  end

  defp foreign_key_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :foreign end)
  end

  defp foreign_key_error?({_tag, %Ecto.Changeset{} = changeset}),
    do: foreign_key_error?(changeset)

  defp foreign_key_error?(_error), do: false

  @doc ~S"""
  Escapes `LIKE` wildcards (`%`, `_`) and the escape character (`\`) in
  user-supplied search input so it matches literally.

  Queries must pair the escaped pattern with an explicit escape clause,
  because SQLite (unlike Postgres) has no default `LIKE` escape character:

      fragment("? LIKE ? ESCAPE '\\'", u.name, ^("%" <> Repo.escape_like(term) <> "%"))
  """
  @spec escape_like(String.t()) :: String.t()
  def escape_like(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc ~S"""
  Builds a case-insensitive "contains" `LIKE` pattern from user search input,
  or `nil` when the input is blank and the caller should not filter at all.

  Pair it with a lowercased column so both adapters agree on case:

      fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern)
  """
  @spec search_pattern(term()) :: String.t() | nil
  def search_pattern(term) when is_binary(term) do
    case term |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> "%" <> escape_like(normalized) <> "%"
    end
  end

  def search_pattern(_term), do: nil

  @doc """
  Like `get/3`, but returns `nil` (instead of raising `Ecto.Query.CastError`)
  when `id` is not a valid UUID. Use for lookups whose id comes from external
  input (URL params, channel payloads, hook args).
  """
  @spec get_uuid(Ecto.Queryable.t(), term(), Keyword.t()) :: Ecto.Schema.t() | nil
  def get_uuid(queryable, id, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> get(queryable, uuid, opts)
      :error -> nil
    end
  end

  @doc """
  Like `get!/3`, but raises `Ecto.NoResultsError` (instead of
  `Ecto.Query.CastError`) when `id` is not a valid UUID, so invalid ids from
  external input surface as 404s rather than 400s.
  """
  @spec get_uuid!(Ecto.Queryable.t(), term(), Keyword.t()) :: Ecto.Schema.t()
  def get_uuid!(queryable, id, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> get!(queryable, uuid, opts)
      :error -> raise Ecto.NoResultsError, queryable: queryable
    end
  end
end
