defmodule GameServerWeb.AdminLive.RateLimiting do
  use GameServerWeb, :live_view

  alias GameServerWeb.Plugs.IpBan

  @refresh_interval 5_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">
          ← Back to Admin
        </.link>

        <div>
          <h1 class="text-3xl font-bold">Rate Limiting & IP Bans</h1>
          <p class="mt-1 text-sm text-base-content/70">
            Manage IP bans and monitor rate limiting across HTTP, Auth, WebSocket, and WebRTC.
          </p>
        </div>

        <%!-- Summary cards --%>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
          <div class="card bg-base-200 p-4">
            <div class="text-xs text-base-content/60">Active IP Bans</div>
            <div class="text-2xl font-bold">{length(@ip_bans)}</div>
          </div>
          <div class="card bg-base-200 p-4">
            <div class="text-xs text-base-content/60">Rate Limited (now)</div>
            <div class={[
              "text-2xl font-bold",
              @rate_stats.limited > 0 && "text-warning"
            ]}>
              {@rate_stats.limited}
            </div>
          </div>
          <div class="card bg-base-200 p-4">
            <div class="text-xs text-base-content/60">Hammer Banned</div>
            <div class={[
              "text-2xl font-bold",
              @rate_stats.banned > 0 && "text-error"
            ]}>
              {@rate_stats.banned}
            </div>
          </div>
          <div class="card bg-base-200 p-4">
            <div class="text-xs text-base-content/60">IPs Tracked</div>
            <div class="text-2xl font-bold">{length(@rate_stats.usage)}</div>
          </div>
          <div class="card bg-base-200 p-4">
            <div class="text-xs text-base-content/60">Ban Log Entries</div>
            <div class="text-2xl font-bold">{length(@ban_log)}</div>
          </div>
        </div>

        <%!-- Per-bucket type breakdown --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">
              Traffic by Bucket Type
              <span class="text-xs font-normal text-base-content/60">(live)</span>
            </h2>
            <div class="grid grid-cols-2 md:grid-cols-5 gap-3 mt-2">
              <%= for {type, label, badge_class} <- bucket_types() do %>
                <% bucket = Map.get(@rate_stats.by_type, type, %{count: 0, limited: 0, total_hits: 0}) %>
                <div class="bg-base-100 rounded-lg p-3">
                  <div class="flex items-center gap-2 mb-1">
                    <span class={["badge badge-xs font-bold", badge_class]}>{label}</span>
                  </div>
                  <div class="text-lg font-bold">
                    {bucket.count} <span class="text-xs font-normal text-base-content/60">IPs</span>
                  </div>
                  <div class="text-xs text-base-content/60">
                    {bucket.total_hits} total hits
                  </div>
                  <%= if bucket.limited > 0 do %>
                    <div class="text-xs text-warning font-semibold">
                      {bucket.limited} rate limited
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Configuration --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">Configuration</h2>
            <p class="text-xs text-base-content/60 mb-3">
              Rate limit settings (set via RATE_LIMIT_* env vars — restart required to change).
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Bucket</th>
                    <th class="text-right">Limit</th>
                    <th class="text-right">Window</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>General (HTTP)</td>
                    <td class="text-right font-mono">{@config.general_limit}</td>
                    <td class="text-right font-mono">{div(@config.general_window, 1000)}s</td>
                  </tr>
                  <tr>
                    <td>Auth (login/register/OAuth)</td>
                    <td class="text-right font-mono">{@config.auth_limit}</td>
                    <td class="text-right font-mono">{div(@config.auth_window, 1000)}s</td>
                  </tr>
                  <tr>
                    <td>WebSocket (per-user)</td>
                    <td class="text-right font-mono">{@config.ws_limit}</td>
                    <td class="text-right font-mono">{div(@config.ws_window, 1000)}s</td>
                  </tr>
                  <tr>
                    <td>WebRTC DataChannel (per-user)</td>
                    <td class="text-right font-mono">{@config.dc_limit}</td>
                    <td class="text-right font-mono">{div(@config.dc_window, 1000)}s</td>
                  </tr>
                  <tr>
                    <td>ICE Candidates (per-user)</td>
                    <td class="text-right font-mono">{@config.ice_limit}</td>
                    <td class="text-right font-mono">{div(@config.ice_window, 1000)}s</td>
                  </tr>
                  <tr>
                    <td>Max DataChannels per peer</td>
                    <td class="text-right font-mono">{@config.max_channels}</td>
                    <td class="text-right font-mono">—</td>
                  </tr>
                  <tr>
                    <td>Max DC message size</td>
                    <td class="text-right font-mono">{format_bytes(@config.max_message_size)}</td>
                    <td class="text-right font-mono">—</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <%!-- Rate Limit Load (all IPs) --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">
              Rate Limit Load — All Tracked IPs
              <span class="text-xs font-normal text-base-content/60">
                ({length(@rate_stats.usage)} entries, auto-refreshes every 5s)
              </span>
            </h2>
            <p class="text-xs text-base-content/60">
              All IPs with active Hammer bucket entries, sorted by usage (descending).
            </p>

            <div class="overflow-x-auto mt-2 max-h-96 overflow-y-auto">
              <table class="table table-sm table-pin-rows">
                <thead>
                  <tr>
                    <th>IP / Type</th>
                    <th class="text-right">Usage</th>
                    <th class="text-right">Limit</th>
                    <th class="text-right">Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={{type, ip, count, limit} <- @rate_stats.usage}
                    id={"usage-#{type}-#{ip}"}
                  >
                    <td class="font-mono text-xs">
                      <span class={[
                        "badge badge-xs font-bold text-[0.6rem] mr-2",
                        type_badge_class(type)
                      ]}>
                        {type_label(type)}
                      </span>
                      {if type in ["ws", "dc", "ice"], do: "User #{ip}", else: ip}
                    </td>
                    <td class="text-right">
                      <div class="flex items-center justify-end gap-2">
                        <div class="w-16 bg-base-300 rounded-full h-1.5">
                          <div
                            class={[
                              "h-1.5 rounded-full",
                              count >= limit && "bg-error",
                              count >= limit * 0.8 && count < limit && "bg-warning",
                              count < limit * 0.8 && "bg-success"
                            ]}
                            style={"width: #{min(count / max(limit, 1) * 100, 100)}%"}
                          >
                          </div>
                        </div>
                        <span class="font-mono text-xs">{count}</span>
                      </div>
                    </td>
                    <td class="text-right font-mono text-xs">{limit}</td>
                    <td class="text-right">
                      <span :if={count >= limit} class="badge badge-error badge-xs">Blocked</span>
                      <span
                        :if={count < limit && count >= limit * 0.8}
                        class="badge badge-warning badge-xs"
                      >
                        High
                      </span>
                      <span :if={count < limit * 0.8} class="badge badge-success badge-xs">
                        OK
                      </span>
                    </td>
                  </tr>
                  <tr :if={@rate_stats.usage == []}>
                    <td colspan="4" class="text-center text-xs text-base-content/40 py-4 italic">
                      No significant traffic in current window.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- IP Ban Management --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">IP Ban Management</h2>

              <%!-- Ban form --%>
              <form phx-submit="ban_ip" class="flex flex-wrap items-end gap-2 mb-4" id="ban-ip-form">
                <div>
                  <label class="label text-xs">IP Address</label>
                  <input
                    type="text"
                    name="ip"
                    placeholder="e.g. 1.2.3.4"
                    class="input input-bordered input-sm w-44"
                    required
                  />
                </div>
                <div>
                  <label class="label text-xs">Duration</label>
                  <select name="duration" class="select select-bordered select-sm">
                    <option value="permanent">Permanent</option>
                    <option value="1h">1 hour</option>
                    <option value="24h">24 hours</option>
                    <option value="7d">7 days</option>
                    <option value="30d">30 days</option>
                  </select>
                </div>
                <button type="submit" class="btn btn-warning btn-sm">
                  <.icon name="hero-no-symbol" class="w-4 h-4" /> Ban IP
                </button>
              </form>

              <%!-- Active bans list --%>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Banned IP</th>
                      <th class="text-right">Expires</th>
                      <th class="text-right">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={{ip, expires} <- @ip_bans} id={"ban-#{ip}"}>
                      <td class="font-mono text-xs font-bold text-error">{ip}</td>
                      <td class="text-right text-xs">
                        <%= if expires == :infinity do %>
                          <span class="badge badge-error badge-xs">Permanent</span>
                        <% else %>
                          <span class="font-mono">{format_ban_ttl(expires)}</span>
                        <% end %>
                      </td>
                      <td class="text-right">
                        <button
                          type="button"
                          phx-click="unban_ip"
                          phx-value-ip={ip}
                          class="btn btn-ghost btn-xs text-success"
                        >
                          Unban
                        </button>
                      </td>
                    </tr>
                    <tr :if={@ip_bans == []}>
                      <td colspan="3" class="text-center text-xs text-base-content/40 py-4 italic">
                        No active IP bans.
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- Ban History Log --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">
                Ban History
                <span class="text-xs font-normal text-base-content/60">(in-memory, last 100)</span>
              </h2>

              <div class="overflow-x-auto max-h-80 overflow-y-auto">
                <table class="table table-sm table-pin-rows">
                  <thead>
                    <tr>
                      <th>Action</th>
                      <th>IP</th>
                      <th class="text-right">Duration</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={entry <- @ban_log} id={"log-#{entry.ip}-#{entry.action}"}>
                      <td>
                        <%= if entry.action == :ban do %>
                          <span class="badge badge-error badge-xs">BAN</span>
                        <% else %>
                          <span class="badge badge-success badge-xs">UNBAN</span>
                        <% end %>
                      </td>
                      <td class="font-mono text-xs">{entry.ip}</td>
                      <td class="text-right text-xs">
                        {format_log_ttl(entry.ttl)}
                      </td>
                    </tr>
                    <tr :if={@ban_log == []}>
                      <td colspan="3" class="text-center text-xs text-base-content/40 py-4 italic">
                        No ban history yet.
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    rl_config = Application.get_env(:game_server_web, GameServerWeb.Plugs.RateLimiter, [])

    config = %{
      general_limit: Keyword.get(rl_config, :general_limit, 1200),
      general_window: Keyword.get(rl_config, :general_window_ms, 60_000),
      auth_limit: Keyword.get(rl_config, :auth_limit, 30),
      auth_window: Keyword.get(rl_config, :auth_window_ms, 60_000),
      ws_limit: Keyword.get(rl_config, :ws_limit, 300),
      ws_window: Keyword.get(rl_config, :ws_window_ms, 10_000),
      dc_limit: Keyword.get(rl_config, :dc_limit, 600),
      dc_window: Keyword.get(rl_config, :dc_window_ms, 10_000),
      ice_limit: Keyword.get(rl_config, :ice_limit, 150),
      ice_window: Keyword.get(rl_config, :ice_window_ms, 30_000),
      max_channels: 1,
      max_message_size: 65_536
    }

    {:ok,
     assign(socket,
       config: config,
       ip_bans: IpBan.list_bans(),
       ban_log: IpBan.list_log(),
       rate_stats: build_rate_limit_stats()
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()

    {:noreply,
     assign(socket,
       ip_bans: IpBan.list_bans(),
       ban_log: IpBan.list_log(),
       rate_stats: build_rate_limit_stats()
     )}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("ban_ip", %{"ip" => ip_str, "duration" => duration}, socket) do
    ip_str = String.trim(ip_str)

    if ip_str == "" do
      {:noreply, put_flash(socket, :error, "IP address is required")}
    else
      ttl =
        case duration do
          "1h" -> :timer.hours(1)
          "24h" -> :timer.hours(24)
          "7d" -> :timer.hours(24 * 7)
          "30d" -> :timer.hours(24 * 30)
          _ -> :infinity
        end

      IpBan.ban(ip_str, ttl)

      {:noreply,
       socket
       |> assign(:ip_bans, IpBan.list_bans())
       |> assign(:ban_log, IpBan.list_log())
       |> put_flash(:info, "Banned IP #{ip_str}")}
    end
  end

  @impl true
  def handle_event("unban_ip", %{"ip" => ip_str}, socket) do
    IpBan.unban(ip_str)

    {:noreply,
     socket
     |> assign(:ip_bans, IpBan.list_bans())
     |> assign(:ban_log, IpBan.list_log())
     |> put_flash(:info, "Unbanned IP #{ip_str}")}
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  defp build_rate_limit_stats do
    now_ms = :os.system_time(:millisecond)

    :ets.tab2list(GameServerWeb.RateLimit)
    |> Enum.reduce(
      %{banned: 0, limited: 0, usage: [], banned_ips: [], by_type: %{}},
      fn
        {{key, _window}, count, expiry}, acc when is_binary(key) ->
          cond do
            String.starts_with?(key, "ip_ban:") ->
              ip = String.replace_prefix(key, "ip_ban:", "")
              remaining = max(0, div(expiry - now_ms, 1000))
              remaining_str = "#{div(remaining, 60)}m #{rem(remaining, 60)}s"
              %{acc | banned: acc.banned + 1, banned_ips: [{ip, remaining_str} | acc.banned_ips]}

            String.contains?(key, ":") ->
              [type, ip] = String.split(key, ":", parts: 2)

              limit =
                case type do
                  "auth" -> 10
                  "dc" -> 300
                  "ws" -> 100
                  "ice" -> 50
                  "lv_auth" -> 10
                  "lv_general" -> 120
                  _ -> 120
                end

              limited_inc = if count >= limit, do: 1, else: 0
              usage = [{type, ip, count, limit} | acc.usage]
              %{acc | limited: acc.limited + limited_inc, usage: usage}

            true ->
              acc
          end

        _, acc ->
          acc
      end
    )
    |> Map.update!(:usage, fn usage ->
      # Aggregate across Hammer time windows: group by {type, ip}
      aggregated =
        usage
        |> Enum.group_by(fn {type, ip, _count, _limit} -> {type, ip} end)
        |> Enum.map(fn {{type, ip}, entries} ->
          max_count = entries |> Enum.map(fn {_, _, c, _} -> c end) |> Enum.max()
          limit = entries |> List.first() |> elem(3)
          {type, ip, max_count, limit}
        end)
        |> Enum.sort_by(fn {_type, _ip, count, _limit} -> count end, :desc)

      aggregated
    end)
    |> then(fn stats ->
      # Build per-bucket-type breakdown from aggregated usage
      by_type =
        stats.usage
        |> Enum.group_by(fn {type, _ip, _count, _limit} -> type end)
        |> Enum.into(%{}, fn {type, entries} ->
          unique_count = length(entries)
          total_hits = entries |> Enum.map(fn {_, _, c, _} -> c end) |> Enum.sum()
          limited = entries |> Enum.count(fn {_, _, c, l} -> c >= l end)
          {type, %{count: unique_count, total_hits: total_hits, limited: limited}}
        end)

      Map.put(stats, :by_type, by_type)
    end)
  rescue
    _ -> %{banned: 0, limited: 0, usage: [], banned_ips: [], by_type: %{}}
  end

  defp bucket_types do
    [
      {"general", "HTTP", "badge-primary"},
      {"auth", "Auth", "badge-warning"},
      {"ws", "WebSocket", "badge-secondary"},
      {"dc", "WebRTC", "badge-info"},
      {"ice", "ICE", "badge-accent"}
    ]
  end

  defp type_badge_class("auth"), do: "badge-warning"
  defp type_badge_class("dc"), do: "badge-info"
  defp type_badge_class("ws"), do: "badge-secondary"
  defp type_badge_class("ice"), do: "badge-accent"
  defp type_badge_class("lv_auth"), do: "badge-warning"
  defp type_badge_class("lv_general"), do: "badge-primary"
  defp type_badge_class(_), do: "badge-primary"

  defp type_label("dc"), do: "WebRTC"
  defp type_label("ws"), do: "WebSocket"
  defp type_label("auth"), do: "Auth"
  defp type_label("ice"), do: "ICE"
  defp type_label("lv_auth"), do: "LV Auth"
  defp type_label("lv_general"), do: "LV General"
  defp type_label(_), do: "HTTP"

  defp format_ban_ttl(expires_mono) do
    remaining_ms = max(expires_mono - System.monotonic_time(:millisecond), 0)

    cond do
      remaining_ms >= 86_400_000 -> "#{div(remaining_ms, 86_400_000)}d"
      remaining_ms >= 3_600_000 -> "#{div(remaining_ms, 3_600_000)}h"
      remaining_ms >= 60_000 -> "#{div(remaining_ms, 60_000)}m"
      true -> "#{div(remaining_ms, 1000)}s"
    end
  end

  defp format_log_ttl(:infinity), do: "permanent"
  defp format_log_ttl(nil), do: "—"

  defp format_log_ttl(ms) when is_integer(ms) do
    cond do
      ms >= 86_400_000 -> "#{div(ms, 86_400_000)}d"
      ms >= 3_600_000 -> "#{div(ms, 3_600_000)}h"
      ms >= 60_000 -> "#{div(ms, 60_000)}m"
      true -> "#{div(ms, 1000)}s"
    end
  end

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
