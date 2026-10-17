defmodule Gamend.Reports do
  @moduledoc """
  Reports about the game itself: a page that broke, a word that is wrong, an
  image that does not match. Filed from `/report` or `POST /api/v1/reports`,
  with or without an account, and worked from `/admin/reports`.

  Not chat reports (`Gamend.Chat.Reports`): those are about a player and lead
  to mutes and warnings. These are about content and lead to a fix.

  ## Kinds

  What a report can be about is a `Gamend.Reports.Kind`. Core has `"page"`; a
  host adds its own with `config :gamend_core, :report_kinds, [Mod, ...]`. A
  configured kind with the key `"page"` replaces core's.

  ## Limits

  Anyone may file one, so every path is capped: per IP per hour at the edge
  (`ip_hourly_limit`, counted in memory by the web layer), per account per day
  and across everyone per day here (`user_daily_limit`, `daily_limit`, counted
  on committed rows, so a restart does not reset them). A signed-in player
  cannot file the same open report twice. Nothing about a sender is stored
  beyond what they typed and, when signed in, their user id.

  ## Hooks

    * `before_report_create/1` — pipeline: `{:ok, attrs}` to file it (changed
      or not), `{:error, reason}` to refuse it.
    * `after_report_created/1` — fire-and-forget.
    * `after_report_resolved/1` — fire-and-forget, each time an open report
      is closed (fixed, wontfix, duplicate). A report reopened and closed
      again fires it again, so anything it pays should carry an idempotency
      key on the report id.

  ## Rewards

  Core pays nothing for a report. A host that pays from
  `after_report_resolved/1` says so in its own words with
  `config :gamend_core, :report_reward, {MyGame.Reports, :reward_text}`
  (`reward_text/1` below): the report page shows the promise to a signed-in
  reader, and the reply to a fixed report's reporter ends on the payment.

  ## Attachments

  Images only (PNG, JPEG, WebP), checked by their bytes, stored under
  `reports/<id>/`. That prefix is never in `Gamend.Storage`'s public list:
  a screenshot can show anything, so only an admin reads it, through
  `attachment/2`.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :reports,
    label: "Reports"

  import Ecto.Query

  require Logger

  alias Gamend.Repo
  alias Gamend.Reports.Kinds.Page
  alias Gamend.Reports.Notices
  alias Gamend.Reports.Report
  alias Gamend.Storage

  setting(:enabled, :boolean,
    default: true,
    doc: "Accept reports from /report and POST /api/v1/reports."
  )

  setting(:daily_limit, :integer,
    default: 500,
    doc: "Most reports accepted in 24 hours across everyone. 0 means no cap."
  )

  setting(:user_daily_limit, :integer,
    default: 20,
    doc: "Most reports one account may file in 24 hours. 0 means no cap."
  )

  setting(:ip_hourly_limit, :integer,
    default: 10,
    doc: "Most reports one IP address may file in an hour (counted in memory). 0 means no cap."
  )

  setting(:max_attachment_bytes, :integer,
    default: 2_000_000,
    doc: "Largest image a report may carry, in bytes."
  )

  setting(:retention_days, :integer,
    default: 180,
    doc:
      "Delete a closed report, and its images, N days after it was closed. Open reports are kept. 0 keeps everything."
  )

  @image_types ~w(image/png image/jpeg image/webp)

  # ── kinds ────────────────────────────────────────────────────────────────

  @doc "Whether reports are being accepted."
  @spec enabled?() :: boolean()
  def enabled?, do: config(:enabled) == true

  @doc "Every kind, configured ones first, core's `page` last unless replaced."
  @spec kinds() :: [module()]
  def kinds do
    configured = Application.get_env(:gamend_core, :report_kinds, [])

    configured
    |> List.insert_at(-1, Page)
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.uniq_by(& &1.key())
  end

  @doc "The kind module for `key`, or nil."
  @spec kind(String.t() | nil) :: module() | nil
  def kind(key) when is_binary(key), do: Enum.find(kinds(), &(&1.key() == key))
  def kind(_key), do: nil

  @doc "The module that draws `kind` on the website, nil for an API-only kind."
  @spec ui(module()) :: module() | nil
  def ui(kind) do
    if Code.ensure_loaded?(kind) and function_exported?(kind, :ui, 0), do: kind.ui(), else: nil
  end

  @doc "Whether a report of `kind` on `topic` must carry a description."
  @spec description_required?(module(), String.t() | nil) :: boolean()
  def description_required?(kind, topic) do
    if function_exported?(kind, :description_required?, 1),
      do: kind.description_required?(topic) == true,
      else: false
  end

  @doc "The image types an attachment may be."
  @spec image_types() :: [String.t()]
  def image_types, do: @image_types

  @doc """
  What the host says a fixed report earns, or nil when it says nothing.

  `:promise` is the line the report page shows a signed-in reader, in the
  reader's locale ("When we fix it, you get 25 coins."); `:paid` is the
  sentence the reply to a fixed report ends on ("You got 25 coins."). Both
  come from `config :gamend_core, :report_reward, {module, fun}`, called as
  `fun.(which)`; a blank answer is nil.
  """
  @spec reward_text(:promise | :paid) :: String.t() | nil
  def reward_text(which) when which in [:promise, :paid] do
    case Application.get_env(:gamend_core, :report_reward) do
      {module, fun} -> blank(apply(module, fun, [which]))
      nil -> nil
    end
  end

  @doc "The resolved value of a setting, for the web layer and tests."
  @spec resolved_config(atom()) :: term()
  def resolved_config(key) when is_atom(key), do: config(key)

  # ── filing ───────────────────────────────────────────────────────────────

  @doc """
  File a report.

  `params` (string keys): `"kind"`, `"topic"`, `"subject"` (map), `"data"`
  (map), `"description"`, `"email"`.

  `context`: `:user_id` (nil for a visitor), `:locale`, `:source` (`"web"` or
  `"api"`), `:client` (a small map of browser facts), `:attachments` (a list
  of image binaries).

  Errors: `:disabled`, `:unknown_kind`, `:invalid_topic`,
  `:description_required`, `:too_many_attachments`, `:attachment_too_large`,
  `:attachment_type`, `:daily_limit`, `:user_daily_limit`,
  `:already_reported`, a kind's own `cast/2` reason, a hook's refusal, or a
  changeset.
  """
  @spec create(map(), map()) :: {:ok, Report.t()} | {:error, term()}
  def create(params, context \\ %{}) when is_map(params) and is_map(context) do
    params = Gamend.Parse.string_keys(params)
    user_id = context[:user_id]
    topic = blank(params["topic"])

    with :ok <- check_enabled(),
         {:ok, kind} <- fetch_kind(params["kind"]),
         :ok <- check_topic(kind, topic),
         {:ok, cast} <- cast_subject(kind, params, context),
         :ok <- check_description(kind, topic, params["description"]),
         {:ok, images} <- check_attachments(kind, context[:attachments] || []),
         :ok <- check_caps(user_id),
         :ok <- check_duplicate(user_id, kind.key(), topic, cast.subject_ref),
         attrs = build_attrs(kind, topic, cast, params, context),
         {:ok, attrs} <- before_hook(attrs),
         {:ok, report} <- insert(attrs) do
      report = store_attachments(report, images)
      dispatch(:after_report_created, [report])
      alert_admins()
      {:ok, report}
    end
  end

  defp check_enabled, do: if(enabled?(), do: :ok, else: {:error, :disabled})

  defp fetch_kind(key) do
    case kind(key) do
      nil -> {:error, :unknown_kind}
      kind -> {:ok, kind}
    end
  end

  defp check_topic(kind, topic) do
    case {kind.topics(), topic} do
      {[], nil} -> :ok
      {[], _topic} -> {:error, :invalid_topic}
      {topics, topic} -> if(topic in topics, do: :ok, else: {:error, :invalid_topic})
    end
  end

  defp cast_subject(kind, params, context) do
    params = %{
      "topic" => blank(params["topic"]),
      "subject" => map_param(params["subject"]),
      "data" => map_param(params["data"])
    }

    case kind.cast(params, Map.take(context, [:user_id, :locale, :source])) do
      {:ok, %{subject: subject, data: data} = cast} when is_map(subject) and is_map(data) ->
        {:ok, Map.put_new(cast, :subject_ref, nil)}

      {:error, _reason} = error ->
        error

      other ->
        Logger.warning("report kind #{inspect(kind)} cast/2 answered #{inspect(other)}")
        {:error, :invalid_subject}
    end
  end

  defp check_description(kind, topic, description) do
    if description_required?(kind, topic) and blank(description) == nil,
      do: {:error, :description_required},
      else: :ok
  end

  defp check_attachments(kind, images) when is_list(images) do
    max_bytes = config(:max_attachment_bytes)

    cond do
      length(images) > kind.max_attachments() ->
        {:error, :too_many_attachments}

      Enum.any?(images, &(not is_binary(&1) or byte_size(&1) > max_bytes)) ->
        {:error, :attachment_too_large}

      true ->
        images
        |> Enum.map(&{&1, Storage.sniff_content_type(&1)})
        |> Enum.reduce_while({:ok, []}, fn {bytes, type}, {:ok, acc} ->
          if type in @image_types,
            do: {:cont, {:ok, [{bytes, type} | acc]}},
            else: {:halt, {:error, :attachment_type}}
        end)
        |> case do
          {:ok, acc} -> {:ok, Enum.reverse(acc)}
          error -> error
        end
    end
  end

  defp check_attachments(_kind, _images), do: {:error, :attachment_type}

  defp check_caps(user_id) do
    cond do
      over?(config(:daily_limit), count_since(nil)) ->
        {:error, :daily_limit}

      user_id && over?(config(:user_daily_limit), count_since(user_id)) ->
        {:error, :user_daily_limit}

      true ->
        :ok
    end
  end

  defp over?(limit, count) when is_integer(limit) and limit > 0, do: count >= limit
  defp over?(_limit, _count), do: false

  defp count_since(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -24, :hour)
    query = from(r in Report, where: r.inserted_at > ^cutoff)
    query = if user_id, do: where(query, [r], r.user_id == ^user_id), else: query
    Repo.aggregate(query, :count, :id)
  end

  # Only a signed-in reporter can be told "you already reported this": a
  # visitor has no identity to compare, and none is stored for them.
  defp check_duplicate(nil, _kind, _topic, _ref), do: :ok
  defp check_duplicate(_user_id, _kind, _topic, nil), do: :ok

  defp check_duplicate(user_id, kind, topic, ref) do
    query =
      from(r in Report,
        where:
          r.user_id == ^user_id and r.kind == ^kind and r.subject_ref == ^ref and
            r.status == "open"
      )

    query =
      if topic, do: where(query, [r], r.topic == ^topic), else: where(query, [r], is_nil(r.topic))

    if Repo.exists?(query), do: {:error, :already_reported}, else: :ok
  end

  defp build_attrs(kind, topic, cast, params, context) do
    %{
      "kind" => kind.key(),
      "topic" => topic,
      "subject_ref" => cast.subject_ref,
      "subject" => cast.subject,
      "data" => cast.data,
      "description" => params["description"],
      "email" => params["email"],
      "locale" => context[:locale],
      "source" => context[:source] || "web",
      "client" => client(context[:client]),
      "user_id" => context[:user_id]
    }
  end

  # A few short strings a bug report needs, never a free-form blob.
  defp client(%{} = client) do
    client
    |> Gamend.Parse.string_keys()
    |> Enum.filter(fn {k, v} ->
      k in ~w(user_agent viewport screen platform app_version) and is_binary(v)
    end)
    |> Map.new(fn {k, v} -> {k, String.slice(v, 0, 300)} end)
  end

  defp client(_client), do: %{}

  defp before_hook(attrs) do
    case Gamend.Hooks.internal_call(:before_report_create, [attrs]) do
      {:ok, %{} = attrs} -> {:ok, attrs}
      {:error, :not_implemented} -> {:ok, attrs}
      {:error, reason} -> {:error, reason}
      _other -> {:ok, attrs}
    end
  end

  defp insert(attrs) do
    %Report{}
    |> Report.changeset(attrs)
    |> Repo.insert()
  end

  # After the insert, so the key carries the report id. A failed upload keeps
  # the report: the words are worth more than the picture.
  defp store_attachments(report, []), do: report

  defp store_attachments(report, images) do
    files =
      images
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{bytes, type}, n} ->
        key = "reports/#{report.id}/#{n}#{Storage.extension_for(type)}"

        case Storage.put(key, bytes, content_type: type, cache_control: "private, no-store") do
          {:ok, key} ->
            [%{"key" => key, "type" => type, "size" => byte_size(bytes)}]

          {:error, reason} ->
            Logger.warning("report #{report.id}: attachment not stored: #{inspect(reason)}")
            []
        end
      end)

    case report |> Report.attachments_changeset(files) |> Repo.update() do
      {:ok, report} -> report
      {:error, _changeset} -> report
    end
  end

  # ── reading ──────────────────────────────────────────────────────────────

  @doc "One report with its users loaded, or nil."
  @spec get(Ecto.UUID.t()) :: Report.t() | nil
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Report |> Repo.get(id) |> Repo.preload([:user, :resolved_by_user])
      :error -> nil
    end
  end

  @doc """
  Reports, newest first. Filters: `:status`, `:kind`, `:topic`,
  `:subject_ref`, `:user_id`, `:q` (text in the description or the subject
  key). Opts: `:page` and `:page_size`; with no `:page`, the first
  `Gamend.Query.unpaginated_limit/0` (an export).
  """
  @spec list(map(), keyword()) :: [Report.t()]
  def list(filters \\ %{}, opts \\ []) do
    filters
    |> query()
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> Gamend.Query.maybe_page(opts)
    |> preload([:user, :resolved_by_user])
    |> Repo.all()
  end

  @doc "How many reports match `filters` (same filters as `list/2`)."
  @spec count(map()) :: non_neg_integer()
  def count(filters \\ %{}), do: filters |> query() |> Repo.aggregate(:count, :id)

  @doc "How many reports are open."
  @spec count_open() :: non_neg_integer()
  def count_open, do: count(%{status: "open"})

  @doc "Reports per status, as `%{status => count}`."
  @spec count_by_status() :: %{String.t() => non_neg_integer()}
  def count_by_status do
    from(r in Report, group_by: r.status, select: {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  How many open reports share each listed report's group (kind, topic,
  subject), as `%{{kind, topic, subject_ref} => count}`. Reports with no
  subject key are not grouped.
  """
  @spec group_counts([Report.t()]) :: %{tuple() => non_neg_integer()}
  def group_counts(reports) do
    refs = reports |> Enum.map(& &1.subject_ref) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if refs == [] do
      %{}
    else
      from(r in Report,
        where: r.status == "open" and r.subject_ref in ^refs,
        group_by: [r.kind, r.topic, r.subject_ref],
        select: {{r.kind, r.topic, r.subject_ref}, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  @doc "The group key `group_counts/1` answers under."
  @spec group_key(Report.t()) :: tuple()
  def group_key(%Report{} = report), do: {report.kind, report.topic, report.subject_ref}

  @doc "Attachment `index` (1-based) of `report`, as `{:ok, bytes, content_type}`."
  @spec attachment(Report.t(), pos_integer()) :: {:ok, binary(), String.t()} | {:error, term()}
  def attachment(%Report{} = report, index) when is_integer(index) and index > 0 do
    case Enum.at(Report.files(report), index - 1) do
      %{"key" => key, "type" => type} ->
        case Storage.get(key) do
          {:ok, bytes} -> {:ok, bytes, type}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :not_found}
    end
  end

  def attachment(_report, _index), do: {:error, :not_found}

  defp query(filters) do
    Enum.reduce(filters, from(r in Report), fn {key, value}, query ->
      filter(query, to_string(key), blank(value))
    end)
  end

  defp filter(query, _key, nil), do: query
  defp filter(query, "status", value), do: where(query, [r], r.status == ^value)
  defp filter(query, "kind", value), do: where(query, [r], r.kind == ^value)
  defp filter(query, "topic", value), do: where(query, [r], r.topic == ^value)
  defp filter(query, "subject_ref", value), do: where(query, [r], r.subject_ref == ^value)
  defp filter(query, "user_id", value), do: where(query, [r], r.user_id == ^value)

  # `LOWER` on both sides: Postgres `LIKE` is case-sensitive, SQLite's is not.
  defp filter(query, "q", value) do
    like = "%" <> (value |> Repo.escape_like() |> String.downcase()) <> "%"

    where(
      query,
      [r],
      fragment("LOWER(?) LIKE ? ESCAPE '\\'", r.description, ^like) or
        fragment("LOWER(?) LIKE ? ESCAPE '\\'", r.subject_ref, ^like) or
        fragment("LOWER(?) LIKE ? ESCAPE '\\'", r.email, ^like)
    )
  end

  defp filter(query, _key, _value), do: query

  # ── working the queue ────────────────────────────────────────────────────

  @doc """
  Close a report (`"fixed"`, `"wontfix"`, `"duplicate"`) or reopen it
  (`"open"`).

  `attrs`: `:resolved_by` (admin user id), `:note` (kept on the report, never
  shown to the reporter), `:message` (sent to the reporter as a notification
  when they had an account; nothing is sent when blank).

  Closing an open report fires `after_report_resolved/1`.
  """
  @spec resolve(Report.t(), String.t(), map()) :: {:ok, Report.t()} | {:error, term()}
  def resolve(%Report{} = report, status, attrs \\ %{}) do
    attrs = Gamend.Parse.string_keys(attrs)

    changes =
      if status == "open" do
        %{
          "status" => "open",
          "resolution_note" => nil,
          "resolved_by" => nil,
          "resolved_at" => nil
        }
      else
        %{
          "status" => status,
          "resolution_note" => blank(attrs["note"]),
          "resolved_by" => attrs["resolved_by"],
          "resolved_at" => DateTime.utc_now(:second)
        }
      end

    case report |> Report.resolve_changeset(changes) |> Repo.update() do
      {:ok, updated} ->
        if report.status == "open" and status != "open" do
          dispatch(:after_report_resolved, [updated])
        end

        maybe_notify_reporter(updated, attrs["message"])
        alert_admins()
        {:ok, updated}

      error ->
        error
    end
  end

  defp maybe_notify_reporter(%Report{user_id: user_id}, message) when is_binary(user_id) do
    case blank(message) do
      nil -> :ok
      message -> Notices.notify_reporter(user_id, message)
    end
  end

  defp maybe_notify_reporter(_report, _message), do: :ok

  @doc "Delete a report and its images."
  @spec delete(Report.t()) :: {:ok, Report.t()} | {:error, term()}
  def delete(%Report{} = report) do
    with {:ok, deleted} <- Repo.delete(report) do
      delete_files(deleted)
      alert_admins()
      {:ok, deleted}
    end
  end

  @doc """
  Delete every report `user_id` filed, images included. Called when the
  account is deleted: a report can carry an email address and a screenshot,
  and an erased account must not leave either behind.
  """
  @spec forget_user(Ecto.UUID.t()) :: non_neg_integer()
  def forget_user(user_id) when is_binary(user_id) do
    from(r in Report, where: r.user_id == ^user_id) |> delete_all_with_files()
  end

  @doc """
  The retention class: closed reports `retention_days` after they were
  closed, images included. Answers how many were deleted.
  """
  @spec prune() :: non_neg_integer()
  def prune do
    case config(:retention_days) do
      days when is_integer(days) and days > 0 ->
        cutoff = DateTime.add(DateTime.utc_now(:second), -days, :day)

        from(r in Report,
          where: r.status != "open" and not is_nil(r.resolved_at) and r.resolved_at < ^cutoff
        )
        |> delete_all_with_files()

      _ ->
        0
    end
  end

  defp delete_all_with_files(query) do
    query
    |> Repo.all()
    |> Enum.reduce(0, fn report, deleted ->
      case Repo.delete(report) do
        {:ok, report} ->
          delete_files(report)
          deleted + 1

        {:error, _} ->
          deleted
      end
    end)
  end

  defp delete_files(report) do
    if Report.files(report) != [] do
      _ = Storage.delete_prefix("reports/#{report.id}/")
    end

    :ok
  end

  # ── plumbing ─────────────────────────────────────────────────────────────

  defp dispatch(hook, args) do
    Gamend.Async.run(fn -> Gamend.Hooks.internal_call(hook, args) end)
    :ok
  end

  defp alert_admins do
    Gamend.Async.run(fn -> Notices.notify_admins(count_open()) end)
    :ok
  end

  defp map_param(%{} = map), do: Gamend.Parse.string_keys(map)
  defp map_param(_value), do: %{}

  defp blank(nil), do: nil

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank(value), do: value

  defp config(key), do: Gamend.Settings.get(__MODULE__, key)
end
