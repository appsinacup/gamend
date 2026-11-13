defmodule Gamend.Accounts.GuestMerge do
  @moduledoc """
  A guest's progress joins the account they log in to.

  A guest (`Gamend.Accounts.User.anonymous?/1`: no email, no provider) who
  signs in to an account they already have used to lose everything they did:
  the session moved to the account and the guest account was deleted. Before
  it is deleted now, its progress is merged into the account
  (`GamendWeb.UserAuth.log_in_user/3` calls `merge/2`).

  One rule throughout: **the account's own data is never overwritten or
  deleted.** The guest's is added where it fits, and what cannot be combined
  stays with the guest account, which nobody can reach once the session has
  moved, and goes with it.

  First the guest's credentials are revoked (`Accounts.revoke_all_tokens/1`):
  its access and refresh tokens and sessions stop working, so a game client
  still signed in as the guest cannot spend what is being moved. Then, in
  order, each step logged and skipped on failure so a sign-in never fails
  because of a merge:

    1. The host (`merge_user_data/2` hook) merges what it understands: its own
       KV keys with its own rules (counts added, histories joined). A key it
       is done with it deletes from the guest, so step 2 leaves it alone.
    2. KV: every guest key the account lacks moves over (`Gamend.KV`, so caches
       and subscribers follow). A key both have stays the account's.
    3. Wallets: each balance is moved, taken off the guest
       (`Gamend.Economy.spend/4`) and added to the account's
       (`Gamend.Economy.grant/4`) in one transaction. A host that grants
       starting coins spends the guest's own grant first in step 1, so it is
       not counted twice.
    4. Inventory: quantities moved the same way (`Gamend.Inventory.consume_item/4`,
       `Gamend.Inventory.grant_item/4`).
    5. Purchases and the entitlements they made
       (`Gamend.Payments.move_purchases/2`): every purchase becomes the
       account's, so its subscription goes on renewing for the account and is
       not cancelled with the guest. A key both hold keeps the row that lasts
       longer. Then entitlements granted without a purchase, through
       `Gamend.Payments.grant_entitlement/3`, which never shortens what the
       account holds. One the account had revoked stays revoked.
    6. Leaderboards: `Gamend.Leaderboards.merge_user_records/2` (best kept,
       counters added, the account's never lowered).
    7. Quests: `Gamend.Quests.merge_user_progress/2` (periods the account has
       not played).
    8. Activity days the account lacks; the guest's analytics events,
       content reports and notifications become the account's.
    9. `users.metadata` and `users.preferences` keys the account lacks.

  Sessions, push tokens, bans, lobby and party seats are not moved. Wallet
  and inventory moves carry idempotency keys and every other step only moves
  what the account lacks, so running it twice adds nothing twice.
  """

  require Logger

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Analytics.Buffer
  alias Gamend.Economy
  alias Gamend.Inventory
  alias Gamend.Lock.Local
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Repo

  require Gamend.Payments.EntitlementStatus, as: EntitlementStatus

  @hook_timeout_ms 30_000

  # Reads of a balance a move gets before it gives up on it: each retry
  # follows a spend that landed between its read and its debit, and the
  # guest's credentials are revoked before the first.
  @move_attempts 3

  @doc """
  Merges `guest`'s progress into `user`, as the moduledoc describes. A no-op
  unless `guest` is a guest and the two differ. Answers `:ok`.
  """
  @spec merge(User.t(), User.t()) :: :ok
  def merge(%User{id: guest_id} = guest, %User{id: user_id} = user) when guest_id != user_id do
    if User.anonymous?(guest) do
      Local.trans({__MODULE__, guest_id}, fn ->
        step(:credentials, fn -> revoke_credentials(guest_id) end)

        step(:host, fn ->
          Gamend.Hooks.internal_call(:merge_user_data, [guest, user],
            timeout_ms: @hook_timeout_ms
          )
        end)

        step(:kv, fn -> merge_kv(guest_id, user_id) end)
        step(:wallets, fn -> merge_wallets(guest_id, user_id) end)
        step(:inventory, fn -> merge_inventory(guest_id, user_id) end)
        step(:purchases, fn -> {:ok, _} = Payments.move_purchases(guest_id, user_id) end)
        step(:entitlements, fn -> merge_entitlements(guest_id, user_id) end)
        step(:leaderboards, fn -> Gamend.Leaderboards.merge_user_records(guest_id, user_id) end)
        step(:quests, fn -> Gamend.Quests.merge_user_progress(guest_id, user_id) end)
        step(:results, fn -> Gamend.Results.move_user(guest_id, user_id) end)
        step(:activity, fn -> merge_activity(guest_id, user_id) end)
        step(:metadata, fn -> merge_metadata(guest_id, user_id) end)
        step(:preferences, fn -> merge_preferences(guest_id, user) end)
      end)

      Logger.info("merged guest #{guest_id} into #{user_id}")
    end

    :ok
  end

  def merge(%User{}, %User{}), do: :ok

  defp step(name, fun) do
    fun.()
  rescue
    e ->
      Logger.error("guest merge #{name} failed: " <> Exception.format(:error, e, __STACKTRACE__))
  catch
    kind, reason ->
      Logger.error("guest merge #{name} failed: #{inspect({kind, reason})}")
  end

  defp merge_kv(guest_id, user_id) do
    for entry <- user_entries(guest_id) do
      case Gamend.KV.get(entry.key, user_id: user_id) do
        {:ok, _account_has_it} ->
          :kept

        :error ->
          {:ok, _} = Gamend.KV.put(entry.key, entry.value, entry.metadata, user_id: user_id)
          :ok = Gamend.KV.delete(entry.key, user_id: guest_id)
      end
    end
  end

  defp user_entries(user_id) do
    Repo.all(
      from(e in Gamend.KV.Entry,
        where: e.user_id == ^user_id and is_nil(e.lobby_id),
        select: %{key: e.key, value: e.value, metadata: e.metadata}
      )
    )
  end

  # Read from the row, not from the struct the caller held: a stale
  # `token_version` bumped by one is the version the guest's tokens carry now.
  defp revoke_credentials(guest_id) do
    case Repo.get(User, guest_id) do
      %User{} = guest -> {:ok, _} = Accounts.revoke_all_tokens(guest)
      nil -> :ok
    end
  end

  # Moved, not copied. The balances were read (through the cache) and granted
  # to the account while the guest kept them until its deletion, which runs
  # after the sign-in and asynchronously; the guest's still-valid token or
  # another socket could spend them meanwhile, so the coins existed twice.
  # Each balance now leaves the guest by the conditional debit and reaches the
  # account in the same transaction: whatever the guest spends first is not
  # moved, and what is moved can no longer be spent by the guest.
  defp merge_wallets(guest_id, user_id) do
    for currency <- held(Gamend.Economy.Wallet, :currency, :balance, guest_id) do
      {:ok, _} = move_currency(guest_id, user_id, currency, @move_attempts)
    end
  end

  defp move_currency(guest_id, user_id, currency, attempts) do
    case amount_held(Gamend.Economy.Wallet, :currency, currency, :balance, guest_id) do
      0 ->
        {:ok, :nothing_held}

      amount ->
        key = "guest_merge:#{guest_id}:#{currency}"

        transfer(
          fn ->
            Economy.spend(guest_id, currency, amount,
              reason: "guest_merge",
              idempotency_key: key <> ":out"
            )
          end,
          fn ->
            Economy.grant(user_id, currency, amount, reason: "guest_merge", idempotency_key: key)
          end
        )
        |> case do
          {:error, :insufficient_funds} when attempts > 1 ->
            move_currency(guest_id, user_id, currency, attempts - 1)

          other ->
            other
        end
    end
  end

  defp merge_inventory(guest_id, user_id) do
    for item <- held(Gamend.Inventory.Item, :item, :quantity, guest_id) do
      {:ok, _} = move_item(guest_id, user_id, item, @move_attempts)
    end
  end

  defp move_item(guest_id, user_id, item, attempts) do
    case amount_held(Gamend.Inventory.Item, :item, item, :quantity, guest_id) do
      0 ->
        {:ok, :nothing_held}

      quantity ->
        key = "guest_merge:#{guest_id}:#{item}"

        transfer(
          fn ->
            Inventory.consume_item(guest_id, item, quantity,
              reason: "guest_merge",
              idempotency_key: key <> ":out"
            )
          end,
          fn ->
            Inventory.grant_item(user_id, item, quantity,
              reason: "guest_merge",
              idempotency_key: key
            )
          end
        )
        |> case do
          {:error, :insufficient_items} when attempts > 1 ->
            move_item(guest_id, user_id, item, attempts - 1)

          other ->
            other
        end
    end
  end

  # Copied, not moved: nothing can spend an entitlement, and the guest's rows
  # go with the guest. A row a purchase made was moved with its purchase in
  # the step before (until 2026-11-13 it stayed, and the guest's delete took
  # it, orphaned the purchase and cancelled its subscription).
  defp merge_entitlements(guest_id, user_id) do
    held =
      user_id
      |> Payments.list_user_entitlements(include_inactive: true)
      |> Map.new(&{&1.key, &1})

    now = DateTime.utc_now(:second)

    for %Entitlement{source_purchase_id: nil} = granted <-
          Payments.list_user_entitlements(guest_id) do
      {:ok, _} = merge_entitlement(granted, Map.get(held, granted.key), user_id, now)
    end
  end

  defp merge_entitlement(granted, nil, user_id, _now) do
    Payments.grant_entitlement(user_id, granted.key,
      expires_at: granted.expires_at,
      metadata: granted.metadata
    )
  end

  # Taken away from the account on purpose, and a grant would bring it back.
  defp merge_entitlement(
         _granted,
         %Entitlement{status: EntitlementStatus.revoked()} = held,
         _user_id,
         _now
       ),
       do: {:ok, held}

  # Only a write that adds something: a grant that changes nothing still tells
  # every `after_entitlement_changed` hook that something did.
  defp merge_entitlement(granted, %Entitlement{} = held, user_id, now) do
    if lasts_as_long?(held, granted, now),
      do: {:ok, held},
      else: Payments.grant_entitlement(user_id, granted.key, expires_at: granted.expires_at)
  end

  defp lasts_as_long?(
         %Entitlement{status: EntitlementStatus.active(), expires_at: nil},
         _granted,
         _now
       ),
       do: true

  defp lasts_as_long?(
         %Entitlement{status: EntitlementStatus.active(), expires_at: %DateTime{} = ends},
         granted,
         now
       ) do
    DateTime.after?(ends, now) and is_struct(granted.expires_at, DateTime) and
      DateTime.compare(ends, granted.expires_at) != :lt
  end

  defp lasts_as_long?(%Entitlement{}, _granted, _now), do: false

  # The guest's currencies (or items) with something in them, from the
  # table, not the cache.
  defp held(schema, name, amount, guest_id) do
    Repo.all(
      from(r in schema,
        where: r.user_id == ^guest_id and field(r, ^amount) > 0,
        select: field(r, ^name)
      )
    )
  end

  defp amount_held(schema, name, value, amount, guest_id) do
    Repo.one(
      from(r in schema,
        where: r.user_id == ^guest_id and field(r, ^name) == ^value,
        select: field(r, ^amount)
      )
    ) || 0
  end

  # Both sides of a move or neither: a debit whose credit failed rolls back.
  # Each side's effects (cache eviction, broadcast, hook) wait for the commit.
  defp transfer(take, give) do
    Gamend.AfterCommit.transaction(fn ->
      with {:ok, _} <- take.(),
           {:ok, _} <- give.() do
        :moved
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp merge_activity(guest_id, user_id) do
    days =
      Repo.all(
        from(d in Gamend.Analytics.ActivityDay, where: d.user_id == ^guest_id, select: d.day)
      )

    # `insert_all` runs no schema autogeneration: an `Ecto.UUID` key is not
    # an `:id`/`:binary_id` one, so the id is ours to give.
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(
        days,
        &%{id: Gamend.UUIDv7.generate(), user_id: user_id, day: &1, inserted_at: now}
      )

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(
      &Repo.insert_all(Gamend.Analytics.ActivityDay, &1,
        on_conflict: :nothing,
        conflict_target: [:user_id, :day]
      )
    )

    _ = Buffer.reassign(guest_id, user_id)

    Repo.update_all(from(e in Gamend.Analytics.Event, where: e.user_id == ^guest_id),
      set: [user_id: user_id]
    )

    Repo.update_all(from(r in Gamend.Reports.Report, where: r.user_id == ^guest_id),
      set: [user_id: user_id]
    )

    Repo.update_all(
      from(n in Gamend.Notifications.Notification, where: n.recipient_id == ^guest_id),
      set: [recipient_id: user_id]
    )
  end

  # Read now, not from the struct the caller held: the host step may have
  # written to it.
  defp merge_metadata(guest_id, user_id) do
    case Repo.get(User, guest_id) do
      %User{metadata: guest_metadata} when is_map(guest_metadata) and guest_metadata != %{} ->
        {:ok, _} =
          Accounts.update_user_metadata(user_id, fn metadata ->
            case Map.drop(guest_metadata, Map.keys(metadata)) do
              missing when missing == %{} -> :unchanged
              missing -> Map.merge(metadata, missing)
            end
          end)

      _ ->
        :ok
    end
  end

  defp merge_preferences(guest_id, user) do
    case Repo.get(User, guest_id) do
      %User{preferences: guest_preferences}
      when is_map(guest_preferences) and guest_preferences != %{} ->
        {:ok, _} = Accounts.Preferences.update(user, &Map.merge(guest_preferences, &1))

      _ ->
        :ok
    end
  end
end
