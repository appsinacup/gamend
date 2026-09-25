defmodule Gamend.Inventory do
  @moduledoc """
  Player item stacks — the non-fungible companion to `Gamend.Economy`.

  Items are free-form string codes (`"health_potion"`, `"sword"`, `"card_374"`);
  each `(user, item)` pair holds a quantity and per-stack `metadata`. Grants and
  consumes are atomic — a consume can never take a stack below zero — and every
  change is recorded in the `inventory_ledger`.

  ## Usage (server-side / hooks)

      Inventory.grant_item(user_id, "health_potion", 3)
      case Inventory.consume_item(user_id, "health_potion", 1) do
        {:ok, remaining} -> :ok
        {:error, :insufficient_items} -> :none_left
      end

      Inventory.quantity(user_id, "health_potion")  #=> 2
      Inventory.inventory(user_id)                  #=> %{"health_potion" => 2}

  ## Idempotency

  Pass `:idempotency_key` so a retried request (network retry, at-least-once
  job) can't double-apply — the second call is a no-op that returns the current
  quantity:

      Inventory.grant_item(user_id, "loot_crate", 1, idempotency_key: "quest:\#{progress_id}:1")

  Like the economy these are **server-authoritative**: expose them from hooks and
  admin tools, never as a raw client "give me items" endpoint.
  """

  import Ecto.Query

  alias Gamend.Inventory.Item
  alias Gamend.Inventory.LedgerEntry
  alias Gamend.Repo

  @type user_id :: Ecto.UUID.t()
  @type item :: String.t()

  @topic_prefix "inventory:user:"

  # ── Reads ───────────────────────────────────────────────────────────────

  @doc "Quantity of one item a user holds (0 when they have none)."
  @spec quantity(user_id(), item()) :: non_neg_integer()
  def quantity(user_id, item) do
    Repo.one(from i in Item, where: i.user_id == ^user_id and i.item == ^item, select: i.quantity) ||
      0
  end

  @doc "All held items for a user, as a `%{item => quantity}` map."
  @spec inventory(user_id()) :: %{item() => non_neg_integer()}
  def inventory(user_id) do
    from(i in Item, where: i.user_id == ^user_id and i.quantity > 0, select: {i.item, i.quantity})
    |> Repo.all()
    |> Map.new()
  end

  # ── Mutations ───────────────────────────────────────────────────────────

  @doc """
  Add `qty` of `item` to a user's inventory.

  Options: `:reason` (ledger label), `:idempotency_key`, `:metadata`.
  Returns `{:ok, new_quantity}`.
  """
  @spec grant_item(user_id(), item(), pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def grant_item(user_id, item, qty, opts \\ []) when is_integer(qty) and qty > 0 do
    change_quantity(user_id, item, qty, opts)
  end

  @doc """
  Remove `qty` of `item`, atomically. `{:error, :insufficient_items}` if the user
  doesn't hold enough — the stack never goes negative.
  """
  @spec consume_item(user_id(), item(), pos_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :insufficient_items | term()}
  def consume_item(user_id, item, qty, opts \\ []) when is_integer(qty) and qty > 0 do
    change_quantity(user_id, item, -qty, opts)
  end

  defp change_quantity(user_id, item, delta, opts) do
    reason = opts |> Keyword.get(:reason, "unspecified") |> to_string()
    idem = Keyword.get(opts, :idempotency_key)
    metadata = Keyword.get(opts, :metadata, %{})

    cond do
      not valid_item?(item) ->
        {:error, :invalid_item}

      # Checked before the write: SQLite cannot tell Ecto which constraint an
      # INSERT violated, so the item stack's foreign key surfaced as a raised
      # `Ecto.ConstraintError` rather than an error tuple — a 500 on an admin
      # grant naming a stale user. See `Gamend.Accounts.user_exists?/1`.
      not Gamend.Accounts.user_exists?(user_id) ->
        {:error, :user_not_found}

      idem && idem_applied?(idem) ->
        {:ok, quantity(user_id, item)}

      true ->
        case run_change(user_id, item, delta, reason, idem, metadata) do
          {:ok, new_qty} = ok ->
            # Post-commit: push to the user's socket and fire the plugin hook.
            broadcast(user_id, item, new_qty, delta)
            change = %{user_id: user_id, item: item, quantity: new_qty, delta: delta}

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_inventory_changed, [change])
            end)

            ok

          other ->
            other
        end
    end
  end

  defp run_change(user_id, item, delta, reason, idem, metadata) do
    Gamend.Ledger.change(
      fn -> apply_delta(user_id, item, delta) end,
      fn new_qty -> record_ledger(user_id, item, delta, new_qty, reason, idem, metadata) end,
      fn -> quantity(user_id, item) end
    )
  end

  defp apply_delta(user_id, item, delta) when delta > 0 do
    on_conflict = from(i in Item, update: [inc: [quantity: ^delta]])

    %Item{}
    |> Item.changeset(%{user_id: user_id, item: item, quantity: delta})
    |> Repo.insert(on_conflict: on_conflict, conflict_target: [:user_id, :item])
    |> case do
      {:ok, _} -> {:ok, quantity(user_id, item)}
      {:error, changeset} -> {:error, {:item_error, changeset}}
    end
  end

  defp apply_delta(user_id, item, delta) when delta < 0 do
    amount = -delta

    {count, _} =
      Repo.update_all(
        from(i in Item,
          where: i.user_id == ^user_id and i.item == ^item and i.quantity >= ^amount
        ),
        inc: [quantity: delta]
      )

    case count do
      1 -> {:ok, quantity(user_id, item)}
      0 -> {:error, :insufficient_items}
    end
  end

  defp record_ledger(user_id, item, delta, quantity_after, reason, idem, metadata) do
    %LedgerEntry{}
    |> LedgerEntry.changeset(%{
      user_id: user_id,
      item: item,
      delta: delta,
      quantity_after: quantity_after,
      reason: reason,
      idempotency_key: idem,
      metadata: metadata
    })
    |> Repo.insert()
    |> case do
      {:ok, entry} -> entry
      {:error, changeset} -> Gamend.Ledger.rollback_insert_error(changeset, :ledger_error)
    end
  end

  defp idem_applied?(idem) do
    Repo.exists?(from l in LedgerEntry, where: l.idempotency_key == ^idem)
  end

  @doc "Set (overwrite) the per-stack metadata for a user's item."
  @spec set_metadata(user_id(), item(), map()) :: {:ok, map()} | {:error, term()}
  def set_metadata(user_id, item, metadata) when is_map(metadata) do
    on_conflict = from(i in Item, update: [set: [metadata: ^metadata]])

    %Item{}
    |> Item.changeset(%{user_id: user_id, item: item, quantity: 0, metadata: metadata})
    |> Repo.insert(on_conflict: on_conflict, conflict_target: [:user_id, :item])
    |> case do
      {:ok, _} -> {:ok, metadata}
      {:error, changeset} -> {:error, {:item_error, changeset}}
    end
  end

  defp valid_item?(item), do: is_binary(item) and byte_size(item) in 1..64

  # ── Realtime ─────────────────────────────────────────────────────────────

  @doc "Subscribe the calling process to a user's live inventory updates."
  @spec subscribe(user_id()) :: :ok | {:error, term()}
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Gamend.PubSub, topic(user_id))

  @doc "Stop receiving a user's inventory updates."
  @spec unsubscribe(user_id()) :: :ok
  def unsubscribe(user_id), do: Phoenix.PubSub.unsubscribe(Gamend.PubSub, topic(user_id))

  defp topic(user_id), do: @topic_prefix <> user_id

  defp broadcast(user_id, item, quantity, delta) do
    Gamend.Broadcast.publish(
      topic(user_id),
      {:inventory_updated, %{item: item, quantity: quantity, delta: delta}}
    )
  end

  # ── Admin reads ──────────────────────────────────────────────────────────

  @doc false
  @spec list_items(keyword()) :: [Item.t()]
  def list_items(opts \\ []) do
    item_query(opts)
    |> order_by([i], asc: i.item)
    |> paginate(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc false
  @spec count_items(keyword()) :: non_neg_integer()
  def count_items(opts \\ []) do
    Repo.aggregate(item_query(opts), :count, :id)
  end

  defp item_query(opts) do
    Item
    |> maybe_filter(:user_id, Keyword.get(opts, :user_id))
    |> maybe_filter(:item, Keyword.get(opts, :item))
  end

  @doc false
  @spec list_ledger(keyword()) :: [LedgerEntry.t()]
  def list_ledger(opts \\ []), do: opts |> ledger_query() |> Gamend.Ledger.list_entries(opts)

  @doc false
  @spec count_ledger(keyword()) :: non_neg_integer()
  def count_ledger(opts \\ []) do
    Repo.aggregate(ledger_query(opts), :count, :id)
  end

  defp ledger_query(opts) do
    LedgerEntry
    |> maybe_filter(:user_id, Keyword.get(opts, :user_id))
    |> maybe_filter(:item, Keyword.get(opts, :item))
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, :user_id, value), do: Gamend.Query.filter_user(query, value)
  defp maybe_filter(query, :item, value), do: where(query, [q], q.item == ^value)

  defp paginate(query, opts), do: Gamend.Query.page(query, opts)
end
