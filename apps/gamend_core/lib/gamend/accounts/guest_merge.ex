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

  In order, each step logged and skipped on failure so a sign-in never fails
  because of a merge:

    1. The host (`merge_user_data/2` hook) merges what it understands: its own
       KV keys with its own rules (counts added, histories joined). A key it
       is done with it deletes from the guest, so step 2 leaves it alone.
    2. KV: every guest key the account lacks moves over (`Gamend.KV`, so caches
       and subscribers follow). A key both have stays the account's.
    3. Wallets: each balance is added to the account's (`Gamend.Economy.grant/4`).
       A host that grants starting coins spends the guest's own grant first in
       step 1, so it is not counted twice.
    4. Inventory: quantities added (`Gamend.Inventory.grant_item/4`).
    5. Leaderboards: `Gamend.Leaderboards.merge_user_records/2` (best kept,
       counters added, the account's never lowered).
    6. Quests: `Gamend.Quests.merge_user_progress/2` (periods the account has
       not played).
    7. Activity days the account lacks; the guest's analytics events,
       content reports and notifications become the account's.
    8. `users.metadata` and `users.preferences` keys the account lacks.

  Sessions, push tokens, bans, lobby and party seats are not moved. Wallet
  and inventory grants carry idempotency keys and every other step only moves
  what the account lacks, so running it twice adds nothing twice.
  """

  require Logger

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Analytics.Buffer
  alias Gamend.Lock.Local
  alias Gamend.Repo

  @hook_timeout_ms 30_000

  @doc """
  Merges `guest`'s progress into `user`, as the moduledoc describes. A no-op
  unless `guest` is a guest and the two differ. Answers `:ok`.
  """
  @spec merge(User.t(), User.t()) :: :ok
  def merge(%User{id: guest_id} = guest, %User{id: user_id} = user) when guest_id != user_id do
    if User.anonymous?(guest) do
      Local.trans({__MODULE__, guest_id}, fn ->
        step(:host, fn ->
          Gamend.Hooks.internal_call(:merge_user_data, [guest, user],
            timeout_ms: @hook_timeout_ms
          )
        end)

        step(:kv, fn -> merge_kv(guest_id, user_id) end)
        step(:wallets, fn -> merge_wallets(guest_id, user_id) end)
        step(:inventory, fn -> merge_inventory(guest_id, user_id) end)
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

  defp merge_wallets(guest_id, user_id) do
    for {currency, balance} <- Gamend.Economy.balances(guest_id), balance > 0 do
      {:ok, _} =
        Gamend.Economy.grant(user_id, currency, balance,
          reason: "guest_merge",
          idempotency_key: "guest_merge:#{guest_id}:#{currency}"
        )
    end
  end

  defp merge_inventory(guest_id, user_id) do
    for {item, quantity} <- Gamend.Inventory.inventory(guest_id), quantity > 0 do
      {:ok, _} =
        Gamend.Inventory.grant_item(user_id, item, quantity,
          reason: "guest_merge",
          idempotency_key: "guest_merge:#{guest_id}:#{item}"
        )
    end
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
