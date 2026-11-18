defmodule Gamend.Notifications.Announcements do
  @moduledoc """
  One notice to every player at once (`Gamend.Notifications.announce_to_all/1`),
  sent from the admin console or the admin API.

  Each player gets it through `Gamend.Notifications.notify/3` in the
  "announcements" group (`Gamend.Notifications.Preferences`), so their choices
  for it apply: the site's row always, the phone unless they turned it off,
  email only if they turned it on. `"site_only"` sends neither.

  Who: every activated account that is not banned, guests included.

  Delivery is one `Gamend.Notifications.AnnouncementWorker` job per batch of
  accounts, in id order: a job sends its batch, then queues the next one. A
  send to many players never holds one long job, and a restart picks up at the
  batch it was on. A batch that fails is retried whole, which repeats nothing a
  player sees twice: the site's row is the player's own (sender = recipient)
  and upserted on its title, a second push replaces the first on the device
  (one collapse key per group), and the email is unique per hour.

  The same title as an earlier announcement refreshes that row (new text,
  unread again) rather than adding a second one.
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Gamend.Accounts.User
  alias Gamend.Bans
  alias Gamend.Notifications
  alias Gamend.Notifications.AnnouncementWorker
  alias Gamend.Repo

  require Gamend.Notifications.NotificationType, as: NotificationType
  require Gamend.Notifications.PreferenceGroup, as: PreferenceGroup

  @batch_size 500
  @fields %{title: :string, content: :string, url: :string, site_only: :boolean}

  @doc """
  The form behind an announcement: `title` (required), `content`, `url` (a
  path on this site the notice leads to, such as `/news`) and `site_only`.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    {%{site_only: false}, @fields}
    |> cast(attrs, Map.keys(@fields))
    |> validate_required([:title])
    |> validate_length(:title, max: Gamend.Limits.get(:max_notification_title))
    |> validate_length(:content, max: Gamend.Limits.get(:max_notification_content))
    |> validate_length(:url, max: Gamend.Limits.get(:max_profile_url))
    |> validate_format(:url, ~r{\A/(?!/)\S*\z},
      message: "must be a path on this site, such as /news"
    )
  end

  @doc """
  Queue `attrs` (see `changeset/1`) for every player. Answers how many
  accounts it is going to (banned ones are skipped as it reaches them).
  """
  @spec send_to_all(map()) :: {:ok, non_neg_integer()} | {:error, Ecto.Changeset.t()}
  def send_to_all(attrs) when is_map(attrs) do
    with {:ok, notice} <- apply_action(changeset(attrs), :insert) do
      args =
        notice
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
        |> Map.merge(%{"id" => Gamend.UUIDv7.generate(), "after" => nil})

      {:ok, _job} = Oban.insert(AnnouncementWorker.new(args))
      {:ok, count_audience()}
    end
  end

  @doc "How many accounts an announcement goes to: every activated one."
  @spec count_audience() :: non_neg_integer()
  def count_audience, do: Repo.aggregate(audience(), :count)

  @doc false
  # One batch: the accounts after `"after"` in id order, then the job for the
  # next batch when this one was full. Queued last, so a batch that raises
  # queues nothing and is retried whole; unique per announcement and cursor,
  # so a job run twice queues its successor once.
  @spec send_batch(map(), pos_integer()) :: :ok
  def send_batch(%{"id" => _id} = args, batch_size \\ @batch_size) do
    users =
      from(u in audience(), order_by: [asc: u.id], limit: ^batch_size)
      |> after_id(args["after"])
      |> Repo.all()

    notice =
      Map.reject(
        %{
          "title" => args["title"],
          "content" => args["content"],
          "url" => args["url"],
          "site_only" => args["site_only"] == true,
          "type" => NotificationType.announcement()
        },
        fn {_key, value} -> is_nil(value) end
      )

    for user <- users,
        not Bans.banned?(:account, user.id),
        do: Notifications.notify(user, PreferenceGroup.announcements(), notice)

    if length(users) == batch_size do
      next = Map.put(args, "after", List.last(users).id)
      {:ok, _job} = Oban.insert(AnnouncementWorker.new(next))
    end

    :ok
  end

  defp audience, do: from(u in User, where: u.is_activated == true)

  defp after_id(query, nil), do: query
  defp after_id(query, id) when is_binary(id), do: where(query, [u], u.id > ^id)
end
