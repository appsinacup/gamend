defmodule Gamend.Notifications.Digest do
  @moduledoc """
  Emails that wait and go out together: a group with `email_every`
  (`Gamend.Notifications.Preferences`) keeps its notices here, and one email
  lists them.

  The clock is the user's oldest waiting notice, per group: a `:week` digest
  goes a week after the first notice in it. So nothing goes out with nothing
  to say, and nobody needs a time zone or a send day. An hourly sweep
  (`Gamend.Notifications.DigestSweeper`) queues what is due, and the web app's
  job (`GamendWeb.Workers.NotificationDigest`) builds and sends it, deleting
  only the rows it listed. A notice that arrives meanwhile waits for the next
  one.

  A notice whose subject is already waiting replaces that one's words and
  keeps its place, as the site's row does (one row per title). A user holds
  at most `max_digest_items_per_user` notices (`Gamend.Limits`). A digest
  that keeps failing (an address that bounces) is given up after 24
  sweeps, a day of them: its notices are deleted, not queued forever.
  """

  import Ecto.Query, only: [from: 2, dynamic: 2]

  require Logger

  alias Gamend.Notifications.DigestItem
  alias Gamend.Notifications.Preferences
  alias Gamend.Repo

  @worker "GamendWeb.Workers.NotificationDigest"
  # A retry or a second node's sweep must not send a user's digest twice.
  @unique [period: 3600, fields: [:worker, :args], keys: [:user_id, :group]]

  # Sweeps that queued a notice's digest before it is given up: hourly, so a day.
  @max_sweeps 24

  @doc """
  Keep a notice for `user_id`'s next digest of `group`. A subject already
  waiting there takes the new words; past the user's cap the notice is left
  out (`{:error, :too_many_items}`).
  """
  @spec add(String.t(), String.t(), map()) :: {:ok, DigestItem.t()} | {:error, term()}
  def add(user_id, group, attrs) do
    item = %DigestItem{
      user_id: user_id,
      group_key: group,
      subject: attrs["subject"] || attrs["title"],
      text: attrs["text"] || attrs["content"] || "",
      url: attrs["url"]
    }

    # The count and the insert under the user's lock: the cap is a count.
    Gamend.Lock.serialize("notification_digest", user_id, fn ->
      held = Repo.aggregate(from(i in DigestItem, where: i.user_id == ^user_id), :count)

      waiting? =
        Repo.exists?(
          from(i in DigestItem,
            where: i.user_id == ^user_id and i.group_key == ^group and i.subject == ^item.subject
          )
        )

      if held >= Gamend.Limits.get(:max_digest_items_per_user) and not waiting?,
        do: Repo.rollback(:too_many_items)

      case Repo.insert(item,
             on_conflict: {:replace, [:text, :url]},
             conflict_target: [:user_id, :group_key, :subject],
             returning: true
           ) do
        {:ok, item} -> item
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "What waits for `user_id` in `group`, oldest first."
  @spec items(String.t(), String.t()) :: [DigestItem.t()]
  def items(user_id, group) do
    from(i in DigestItem,
      where: i.user_id == ^user_id and i.group_key == ^group,
      order_by: [asc: i.inserted_at, asc: i.id]
    )
    |> Repo.all()
  end

  @doc "Delete exactly these rows: what arrived after they were read stays."
  @spec delete([DigestItem.t()]) :: non_neg_integer()
  def delete(items) do
    ids = Enum.map(items, & &1.id)
    {count, _} = Repo.delete_all(from(i in DigestItem, where: i.id in ^ids))
    count
  end

  @doc """
  The `{user_id, group}` pairs due at `now`. A group that no longer declares
  `email_every` is due at once, so a host dropping it strands nothing.
  """
  @spec due(DateTime.t()) :: [{String.t(), String.t()}]
  def due(now \\ DateTime.utc_now(:second)) do
    # A pair is due when any of its notices is as old as its group's period,
    # which is its oldest being so: asked of the `(group_key, inserted_at)`
    # index, not by grouping the whole table every hour.
    from(i in DigestItem,
      where: ^due_rows(now),
      distinct: true,
      select: {i.user_id, i.group_key}
    )
    |> Repo.all()
  end

  defp due_rows(now) do
    periods =
      for %{key: key} <- Preferences.groups(),
          (days = Preferences.email_every_days(key)) > 0,
          do: {key, DateTime.add(now, -days, :day)}

    keys = Enum.map(periods, &elem(&1, 0))

    Enum.reduce(periods, dynamic([i], i.group_key not in ^keys), fn {key, cutoff}, due ->
      dynamic([i], ^due or (i.group_key == ^key and i.inserted_at <= ^cutoff))
    end)
  end

  @doc """
  Queue every digest due at `now`, after giving up the notices whose digest
  was queued `#{@max_sweeps}` times and never sent. Returns how many pairs
  were due.
  """
  @spec sweep(DateTime.t()) :: non_neg_integer()
  def sweep(now \\ DateTime.utc_now(:second)) do
    case Repo.delete_all(from(i in DigestItem, where: i.sweeps >= @max_sweeps)) do
      {0, _} -> :ok
      {count, _} -> Logger.warning("notification digests: gave up #{count} notices never sent")
    end

    due = due(now)

    Enum.each(due, fn {user_id, group} ->
      {:ok, _job} =
        %{"user_id" => user_id, "group" => group}
        |> Oban.Job.new(worker: @worker, queue: :mailers, max_attempts: 5, unique: @unique)
        |> Oban.insert()
    end)

    # Counted on the notices that made their pair due: a digest that is sent
    # deletes them, one that keeps failing reaches `@max_sweeps`.
    _ = Repo.update_all(from(i in DigestItem, where: ^due_rows(now)), inc: [sweeps: 1])

    length(due)
  end
end
