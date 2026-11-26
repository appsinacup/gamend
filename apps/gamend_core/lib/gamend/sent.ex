defmodule Gamend.Sent do
  @moduledoc """
  What went out: one row per email (`Gamend.Accounts.UserNotifier`) and per
  push to a device (`Gamend.Push.DeliveryWorker`), for the admin's Sent card
  on `/admin/notifications`.

  A row keeps what the person got, so the admin can see it in its own look:
  an email's `Gamend.Mail.Message` (`message/1` rebuilds it, and
  `Gamend.Mail.Message.to_html/1` draws it in today's email layout), a push's
  title and text. What would let someone else act as the reader is hidden
  before it is stored: a sign-in or confirmation link, a code, an unsubscribe
  link.

  An announcement's sends share its id (`batch_id`), so `list_lines/2` shows
  one send to everyone as one line, and `list/2` with `"batch_id"` lists who
  got it.

  Recording never stops a send: a row that cannot be written is logged and
  left out. Rows go after `GAMEND_RETENTION_SENT_MESSAGES_DAYS` (30), and with
  their user.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Gamend.Mail.Message
  alias Gamend.Query
  alias Gamend.Repo
  alias Gamend.Sent.SentMessage

  require Gamend.Notifications.NotificationChannel, as: NotificationChannel
  require Gamend.Sent.SentStatus, as: SentStatus

  @hidden "[hidden]"
  @hidden_code "••••••"
  @max_string 255

  @type line :: %{
          key: Ecto.UUID.t(),
          batch?: boolean(),
          count: non_neg_integer(),
          failed: non_neg_integer(),
          kind: String.t(),
          group_key: String.t() | nil,
          subject: String.t() | nil,
          last_at: DateTime.t(),
          row: SentMessage.t() | nil
        }

  @doc """
  Record an email that was sent (or failed). `opts`: `:user_id`, `:group`,
  `:batch`, `:status` (`sent`), `:reason`, and `:secrets`, the strings to hide
  wherever they appear (a link that signs in, an unsubscribe link). A code is
  always hidden.
  """
  @spec record_email(String.t(), String.t() | nil, String.t() | nil, Message.t(), keyword()) ::
          {:ok, SentMessage.t()} | {:error, term()}
  def record_email(kind, address, subject, %Message{} = message, opts \\ []) do
    secrets = Enum.filter(opts[:secrets] || [], &(is_binary(&1) and &1 != ""))

    insert(%{
      channel: NotificationChannel.email(),
      kind: kind,
      group_key: opts[:group],
      batch_id: opts[:batch],
      user_id: opts[:user_id],
      address: cap(address),
      subject: cap(hide(subject, secrets)),
      body: email_body(message, secrets),
      status: opts[:status] || SentStatus.sent(),
      reason: reason(opts[:reason])
    })
  end

  @doc """
  Record one push to one device: `message` is the push as it was queued
  (`Gamend.Push.Message.to_map/1`), `device` the token's `platform` and
  `provider`. `opts`: `:group`, `:batch`, `:reason`.
  """
  @spec record_push(String.t(), String.t(), map(), map(), String.t(), keyword()) ::
          {:ok, SentMessage.t()} | {:error, term()}
  def record_push(kind, user_id, message, device, status, opts \\ []) do
    insert(%{
      channel: NotificationChannel.push(),
      kind: kind,
      group_key: opts[:group],
      batch_id: opts[:batch],
      user_id: user_id,
      address: cap(Enum.map_join([device[:platform], device[:provider]], " · ", &to_string/1)),
      subject: cap(message["title"]),
      body: Map.take(message, ["title", "body", "image", "data"]),
      status: status,
      reason: reason(opts[:reason])
    })
  end

  defp insert(attrs) do
    case %SentMessage{} |> SentMessage.changeset(attrs) |> Repo.insert() do
      {:ok, sent} ->
        {:ok, sent}

      {:error, changeset} ->
        Logger.error("[sent] not recorded: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  rescue
    # Best effort: the email or push already went, and a retry would send it
    # again.
    e ->
      Logger.error("[sent] not recorded: " <> Exception.format(:error, e, __STACKTRACE__))
      {:error, :not_recorded}
  end

  defp email_body(%Message{} = message, secrets) do
    hide = &hide(&1, secrets)

    %{
      "title" => hide.(message.title),
      "paragraphs" => Enum.map(message.paragraphs, hide),
      "button" =>
        case message.button do
          {label, url} -> [label, hide.(url)]
          nil -> nil
        end,
      "code" => if(message.code, do: @hidden_code),
      "image" => message.image,
      "items" =>
        Enum.map(message.items, fn item ->
          %{
            "title" => hide.(item[:title]),
            "text" => hide.(item[:text]),
            "url" => hide.(item[:url])
          }
        end),
      "footer" => Enum.map(message.footer, hide)
    }
  end

  defp hide(nil, _secrets), do: nil

  defp hide(text, secrets) when is_binary(text),
    do: Enum.reduce(secrets, text, &String.replace(&2, &1, @hidden))

  defp cap(nil), do: nil
  defp cap(text) when is_binary(text), do: String.slice(text, 0, @max_string)

  defp reason(nil), do: nil
  defp reason(text) when is_binary(text), do: cap(text)
  defp reason(other), do: cap(inspect(other))

  @doc "An email row's message, rebuilt from what was stored; nil for a push."
  @spec message(SentMessage.t()) :: Message.t() | nil
  def message(%SentMessage{channel: NotificationChannel.email(), body: body}) do
    %Message{
      title: body["title"] || "",
      paragraphs: body["paragraphs"] || [],
      button:
        case body["button"] do
          [label, url] -> {label, url}
          _none -> nil
        end,
      code: body["code"],
      image: body["image"],
      items:
        Enum.map(body["items"] || [], &%{title: &1["title"], text: &1["text"], url: &1["url"]}),
      footer: body["footer"] || []
    }
  end

  def message(%SentMessage{}), do: nil

  @doc "One row, with its user."
  @spec get(term()) :: SentMessage.t() | nil
  def get(id) do
    case Repo.get_uuid(SentMessage, id) do
      nil -> nil
      sent -> Repo.preload(sent, :user)
    end
  end

  @doc """
  Rows, newest first, with their users. `filters` (string keys, all optional):
  `"channel"`, `"kind"`, `"status"`, `"failed"` (`true`: anything not sent),
  `"batch_id"`, `"user_id"`, `"search"` (part of the address or subject).
  """
  @spec list(map(), keyword()) :: [SentMessage.t()]
  def list(filters \\ %{}, opts \\ []) do
    filters
    |> filtered()
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> Query.page(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "How many rows `list/2` pages through."
  @spec count(map()) :: non_neg_integer()
  def count(filters \\ %{}), do: Repo.aggregate(filtered(filters), :count)

  @doc """
  The rows as lines, newest first: one per email or push, and one per
  announcement, which carries how many went and how many did not. A line of
  one send carries its row. Same `filters` as `list/2`.
  """
  @spec list_lines(map(), keyword()) :: [line()]
  def list_lines(filters \\ %{}, opts \\ []) do
    sent = SentStatus.sent()

    lines =
      from(s in filtered(filters),
        group_by: coalesce(s.batch_id, s.id),
        order_by: [desc: max(s.inserted_at), desc: coalesce(s.batch_id, s.id)],
        select: %{
          key: type(coalesce(s.batch_id, s.id), Ecto.UUID),
          batched: count(s.batch_id),
          count: count(s.id),
          failed: sum(fragment("CASE WHEN ? = ? THEN 0 ELSE 1 END", s.status, ^sent)),
          kind: max(s.kind),
          group_key: max(s.group_key),
          subject: max(s.subject),
          last_at: max(s.inserted_at)
        }
      )
      |> Query.page(opts)
      |> Repo.all()

    single_ids = for %{batched: 0, key: key} <- lines, do: key

    rows =
      from(s in SentMessage, where: s.id in ^single_ids, preload: :user)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.map(lines, fn %{batched: batched} = line ->
      line
      |> Map.delete(:batched)
      |> Map.merge(%{batch?: batched > 0, failed: line.failed || 0, row: rows[line.key]})
    end)
  end

  @doc "How many lines `list_lines/2` pages through."
  @spec count_lines(map()) :: non_neg_integer()
  def count_lines(filters \\ %{}) do
    keys =
      from(s in filtered(filters),
        group_by: coalesce(s.batch_id, s.id),
        select: %{key: coalesce(s.batch_id, s.id)}
      )

    Repo.one(from(k in subquery(keys), select: count()))
  end

  defp filtered(filters) do
    Enum.reduce(filters, from(s in SentMessage), fn
      {_key, value}, query when value in [nil, ""] -> query
      {"channel", channel}, query -> where(query, [s], s.channel == ^channel)
      # literal-ok: a filter's key, the shape of the map
      {"kind", kind}, query -> where(query, [s], s.kind == ^kind)
      # literal-ok: a filter's key, the shape of the map
      {"status", status}, query -> where(query, [s], s.status == ^status)
      {"failed", true}, query -> where(query, [s], s.status != ^SentStatus.sent())
      {"batch_id", id}, query -> where_uuid(query, :batch_id, id)
      # literal-ok: a filter's key, the shape of the map
      {"user_id", id}, query -> where_uuid(query, :user_id, id)
      # literal-ok: a filter's key, the shape of the map
      {"search", text}, query -> search(query, text)
      _other, query -> query
    end)
  end

  defp where_uuid(query, field, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> where(query, [s], field(s, ^field) == ^uuid)
      :error -> where(query, false)
    end
  end

  defp search(query, text) do
    case Repo.search_pattern(text) do
      nil ->
        query

      pattern ->
        where(
          query,
          [s],
          fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", s.address, ^pattern) or
            fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", s.subject, ^pattern)
        )
    end
  end
end
