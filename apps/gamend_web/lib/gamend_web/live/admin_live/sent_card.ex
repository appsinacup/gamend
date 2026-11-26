defmodule GamendWeb.AdminLive.SentCard do
  @moduledoc """
  The Sent card on `/admin/notifications` (`GamendWeb.AdminLive.Notifications`
  holds its state, in the URL): every email and push that went out
  (`Gamend.Sent`), newest first. An announcement is one line with how many it
  reached; opening it lists who got it. An open line shows what its reader
  saw: an email in the email's own look (and its plain-text copy), a push as
  a phone shows it.
  """

  use GamendWeb, :html

  alias Gamend.Sent.SentMessage
  alias GamendWeb.NotificationEmail

  require Gamend.Notifications.NotificationChannel, as: NotificationChannel
  require Gamend.Sent.SentKind, as: SentKind
  require Gamend.Sent.SentStatus, as: SentStatus

  @kind_labels %{
    SentKind.login_link() => "Log-in link",
    SentKind.confirm_account() => "Confirm account",
    SentKind.change_email() => "Change email",
    SentKind.login_code() => "Log-in code",
    SentKind.password_code() => "Password code",
    SentKind.deletion_warning() => "Deletion warning",
    SentKind.account_approved() => "Account approved",
    SentKind.notification() => "Notification",
    SentKind.digest() => "Digest",
    SentKind.test() => "Test",
    SentKind.other() => "Other"
  }

  @doc "What a kind reads as."
  @spec kind_label(String.t()) :: String.t()
  def kind_label(kind), do: Map.get(@kind_labels, kind, kind)

  attr :channel, :string, required: true
  attr :lines, :list, required: true
  attr :count, :integer, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :search, :string, required: true
  attr :failed, :boolean, required: true
  attr :retention_days, :integer, required: true
  attr :open, :map, default: nil

  @doc "The card."
  def sent_card(assigns) do
    ~H"""
    <div id="admin-sent" class="card bg-base-200">
      <div class="card-body space-y-4">
        <div>
          <h2 class="card-title">Sent</h2>
          <p class="text-sm text-muted">
            Every email and phone notification that went out{retention_text(@retention_days)}.
            A send to everyone is one line. Sign-in links, codes and unsubscribe links are hidden.
          </p>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-3">
          <div role="tablist" class="tabs tabs-box w-fit">
            <button
              :for={
                {channel, label} <- [
                  {NotificationChannel.email(), "Emails"},
                  {NotificationChannel.push(), "Phone"}
                ]
              }
              type="button"
              role="tab"
              id={"admin-sent-tab-" <> channel}
              phx-click="sent_channel"
              phx-value-channel={channel}
              aria-selected={to_string(@channel == channel)}
              class={["tab", @channel == channel && "tab-active"]}
            >
              {label}
            </button>
          </div>

          <form
            id="admin-sent-filter"
            phx-change="sent_filter"
            phx-submit="sent_filter"
            class="flex flex-wrap items-center gap-3"
          >
            <input
              type="search"
              name="search"
              value={@search}
              placeholder={search_placeholder(@channel)}
              aria-label="Search sent"
              phx-debounce="300"
              class="input input-bordered input-sm w-56"
            />
            <label class="label cursor-pointer gap-2 text-sm">
              <input type="hidden" name="failed" value="false" />
              <input
                type="checkbox"
                name="failed"
                value="true"
                checked={@failed}
                class="checkbox checkbox-sm"
              /> Not sent only
            </label>
          </form>
        </div>

        <.sent_detail :if={@open} open={@open} channel={@channel} />

        <div class="overflow-x-auto">
          <table class="table table-zebra w-full min-w-[44rem]">
            <thead>
              <tr>
                <th>When</th>
                <th>Kind</th>
                <th>To</th>
                <th>{if @channel == NotificationChannel.email(), do: "Subject", else: "Title"}</th>
                <th>Result</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@lines == []}>
                <td colspan="6" class="text-sm text-muted">Nothing to show.</td>
              </tr>
              <tr
                :for={line <- @lines}
                id={"admin-sent-line-" <> line.key}
                class={[@open && @open.line.key == line.key && "bg-base-300"]}
              >
                <td class="text-sm whitespace-nowrap"><.timestamp at={line.last_at} /></td>
                <td class="text-sm whitespace-nowrap">
                  {kind_label(line.kind)}
                  <span :if={line.group_key} class="block text-xs text-muted">
                    {NotificationEmail.group_label(line.group_key)}
                  </span>
                </td>
                <td class="text-sm">
                  <%= if line.batch? do %>
                    <span class="badge badge-sm badge-info gap-1">
                      <.icon name="hero-user-group-solid" class="size-3" /> {people(line.count)}
                    </span>
                  <% else %>
                    <.recipient row={line.row} />
                  <% end %>
                </td>
                <td class="text-sm max-w-xs truncate">{line.subject || "-"}</td>
                <td class="text-sm whitespace-nowrap">
                  <.line_result line={line} />
                </td>
                <td class="text-sm">
                  <button
                    type="button"
                    phx-click="sent_open"
                    phx-value-key={line.key}
                    class="btn btn-xs btn-surface"
                  >
                    <.icon name="hero-eye-solid" class="size-4" /> Open
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.pagination
          page={@page}
          total_pages={@total_pages}
          total_count={@count}
          on_prev="sent_prev"
          on_next="sent_next"
        />
      </div>
    </div>
    """
  end

  attr :open, :map, required: true
  attr :channel, :string, required: true

  defp sent_detail(assigns) do
    ~H"""
    <div id="admin-sent-detail" class="rounded-box bg-base-100 p-4 space-y-4">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="space-y-1">
          <h3 class="font-semibold">{@open.line.subject || "-"}</h3>
          <p class="text-sm text-muted">
            {kind_label(@open.line.kind)}
            <span :if={@open.line.group_key}>
              · {NotificationEmail.group_label(@open.line.group_key)}
            </span>
            <span :if={@open.line.batch?}>
              · sent to {people(@open.line.count)}, {@open.line.count - @open.line.failed} reached
            </span>
          </p>
        </div>
        <button
          type="button"
          phx-click="sent_close"
          class="btn btn-sm btn-ghost"
          aria-label="Close"
        >
          <.icon name="hero-x-mark-solid" class="size-4" /> Close
        </button>
      </div>

      <div :if={@open.line.batch?} class="space-y-2">
        <div class="overflow-x-auto max-h-72">
          <table class="table table-sm w-full">
            <thead>
              <tr>
                <th>To</th>
                <th>When</th>
                <th>Result</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @open.rows}
                id={"admin-sent-row-" <> row.id}
                class={[@open.row && @open.row.id == row.id && "bg-base-200"]}
              >
                <td class="text-sm"><.recipient row={row} /></td>
                <td class="text-sm whitespace-nowrap"><.timestamp at={row.inserted_at} /></td>
                <td class="text-sm"><.row_result row={row} /></td>
                <td>
                  <button
                    type="button"
                    phx-click="sent_row"
                    phx-value-id={row.id}
                    class="btn btn-xs btn-ghost"
                  >
                    <.icon name="hero-eye-solid" class="size-4" /> Show
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <.pagination
          page={@open.rows_page}
          total_pages={@open.rows_total_pages}
          total_count={@open.rows_count}
          on_prev="sent_rows_prev"
          on_next="sent_rows_next"
        />
      </div>

      <div :if={@open.row} class="space-y-3">
        <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
          <dt class="text-muted">To</dt>
          <dd><.recipient row={@open.row} /></dd>
          <dt class="text-muted">Sent</dt>
          <dd><.timestamp at={@open.row.inserted_at} format="datetime" /></dd>
          <dt class="text-muted">Result</dt>
          <dd>
            <.row_result row={@open.row} />
            <span :if={@open.row.reason} class="block font-mono text-xs text-muted break-all">
              {@open.row.reason}
            </span>
          </dd>
        </dl>

        <%= if @channel == NotificationChannel.email() do %>
          <.email_preview html={@open.html} text={@open.text} />
        <% else %>
          <.push_preview row={@open.row} site={@open.site} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :html, :string, default: nil
  attr :text, :string, required: true

  defp email_preview(assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-xs text-muted">
        As the reader saw it, drawn in today's email layout.
      </p>
      <iframe
        :if={@html}
        id="admin-sent-email-preview"
        title="Email preview"
        sandbox="allow-same-origin"
        srcdoc={@html}
        class="w-full h-[36rem] rounded-box border border-base-300 bg-white"
      ></iframe>
      <details class="text-sm">
        <summary class="cursor-pointer text-muted">Plain-text copy</summary>
        <pre class="mt-2 whitespace-pre-wrap break-words rounded-box bg-base-200 p-3 text-xs">{@text}</pre>
      </details>
    </div>
    """
  end

  attr :row, SentMessage, required: true
  attr :site, :string, required: true

  defp push_preview(assigns) do
    body = assigns.row.body || %{}
    assigns = assign(assigns, body: body, url: get_in(body, ["data", "url"]))

    ~H"""
    <div class="space-y-3">
      <p class="text-xs text-muted">As a phone shows it.</p>
      <div
        id="admin-sent-push-preview"
        class="max-w-sm rounded-box bg-base-200 p-3 shadow-sm space-y-1"
      >
        <div class="flex items-center gap-2 text-xs text-muted">
          <.icon name="hero-device-phone-mobile-solid" class="size-4" />
          <span class="font-semibold uppercase tracking-wide">{@site}</span>
          <span class="ml-auto">now</span>
        </div>
        <p class="text-sm font-semibold">{@body["title"] || "-"}</p>
        <p :if={@body["body"] not in [nil, ""]} class="text-sm">{@body["body"]}</p>
      </div>
      <p :if={@url} class="text-xs text-muted">
        Opens <span class="font-mono">{@url}</span>
      </p>
    </div>
    """
  end

  attr :row, :any, required: true

  defp recipient(%{row: nil} = assigns), do: ~H"-"

  defp recipient(assigns) do
    ~H"""
    <div class="flex items-center gap-2 min-w-0">
      <.user_avatar :if={@row.user} user={@row.user} class="size-6 shrink-0" />
      <div class="min-w-0">
        <span :if={@row.user} class="block truncate">{user_display(@row.user)}</span>
        <span class={["block truncate", @row.user && "text-xs text-muted"]}>
          {@row.address || "-"}
        </span>
      </div>
    </div>
    """
  end

  attr :line, :map, required: true

  defp line_result(%{line: %{batch?: false, row: %SentMessage{}}} = assigns),
    do: ~H"<.row_result row={@line.row} />"

  defp line_result(assigns) do
    ~H"""
    <span class="badge badge-sm badge-success">{@line.count - @line.failed} sent</span>
    <span :if={@line.failed > 0} class="badge badge-sm badge-error">
      {@line.failed} not sent
    </span>
    """
  end

  attr :row, SentMessage, required: true

  defp row_result(assigns) do
    ~H"""
    <span class={["badge badge-sm", result_class(@row.status)]}>{result_label(@row.status)}</span>
    """
  end

  defp result_label(SentStatus.sent()), do: "Sent"
  defp result_label(SentStatus.invalid()), do: "Dead device"
  defp result_label(_failed), do: "Failed"

  defp result_class(SentStatus.sent()), do: "badge-success"
  defp result_class(SentStatus.invalid()), do: "badge-warning"
  defp result_class(_failed), do: "badge-error"

  defp people(1), do: "1 person"
  defp people(count), do: "#{count} people"

  defp search_placeholder(NotificationChannel.email()), do: "Address or subject"
  defp search_placeholder(_push), do: "Device or title"

  defp retention_text(days) when is_integer(days) and days > 0, do: " in the last #{days} days"
  defp retention_text(_kept), do: ""
end
