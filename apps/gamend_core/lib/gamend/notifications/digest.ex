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
  """

  import Ecto.Query, only: [from: 2]

  alias Gamend.Notifications.DigestItem
  alias Gamend.Notifications.Preferences
  alias Gamend.Repo

  @worker "GamendWeb.Workers.NotificationDigest"
  # A retry or a second node's sweep must not send a user's digest twice.
  @unique [period: 3600, fields: [:worker, :args], keys: [:user_id, :group]]

  @doc "Keep a notice for `user_id`'s next digest of `group`."
  @spec add(String.t(), String.t(), map()) :: {:ok, DigestItem.t()} | {:error, term()}
  def add(user_id, group, attrs) do
    Repo.insert(%DigestItem{
      user_id: user_id,
      group_key: group,
      subject: attrs["subject"] || attrs["title"],
      text: attrs["text"] || attrs["content"] || "",
      url: attrs["url"]
    })
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
    from(i in DigestItem,
      group_by: [i.user_id, i.group_key],
      select: {i.user_id, i.group_key, min(i.inserted_at)}
    )
    |> Repo.all()
    |> Enum.filter(fn {_user_id, group, oldest} ->
      DateTime.diff(now, oldest, :day) >= Preferences.email_every_days(group)
    end)
    |> Enum.map(fn {user_id, group, _oldest} -> {user_id, group} end)
  end

  @doc "Queue every digest due at `now`. Returns how many pairs were due."
  @spec sweep(DateTime.t()) :: non_neg_integer()
  def sweep(now \\ DateTime.utc_now(:second)) do
    due = due(now)

    Enum.each(due, fn {user_id, group} ->
      {:ok, _job} =
        %{"user_id" => user_id, "group" => group}
        |> Oban.Job.new(worker: @worker, queue: :mailers, max_attempts: 5, unique: @unique)
        |> Oban.insert()
    end)

    length(due)
  end
end
