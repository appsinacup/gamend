defmodule GameServerWeb.AdminLive.Settings do
  @moduledoc """
  Every declared setting, grouped, with its effective value and where that
  value came from.

  Read-only by design. Settings resolve once at boot — most of them configure
  things Phoenix, Ecto and Nebulex read a single time — so an editable field
  here would promise a change it could not deliver. What this page does
  guarantee is that the list is complete: it renders `GameServer.Settings.all/0`,
  the same declaration that generates `.env.example` and derives every
  environment variable name — every one of them, without exception.

  Variables that other software reads (`RELEASE_COOKIE`, `FLY_REGION`) are not
  settings and are deliberately absent; the Config page reports those.
  """

  use GameServerWeb, :live_view

  alias GameServer.Settings

  @impl true
  def mount(_params, _session, socket) do
    {failures, warnings} = Settings.validate(environment())

    {:ok,
     socket
     |> assign(:filter, "")
     |> assign(:group_filter, nil)
     |> assign(:failures, failures)
     |> assign(:warnings, warnings)
     |> assign(:groups, Settings.groups())
     |> assign_rows()}
  end

  @impl true
  def handle_event("filter", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:filter, value) |> assign_rows()}
  end

  def handle_event("group", %{"group" => ""}, socket) do
    {:noreply, socket |> assign(:group_filter, nil) |> assign_rows()}
  end

  def handle_event("group", %{"group" => group}, socket) do
    {:noreply, socket |> assign(:group_filter, String.to_existing_atom(group)) |> assign_rows()}
  end

  defp assign_rows(socket) do
    filter = String.downcase(socket.assigns.filter)
    group_filter = socket.assigns.group_filter

    rows =
      Settings.all()
      |> Enum.map(&Settings.describe/1)
      |> Enum.filter(fn row ->
        (is_nil(group_filter) or row.group == group_filter) and matches?(row, filter)
      end)
      |> Enum.group_by(& &1.label)
      |> Enum.sort_by(&elem(&1, 0))

    assign(socket, :rows, rows)
  end

  defp matches?(_row, ""), do: true

  defp matches?(row, filter) do
    haystack =
      String.downcase("#{row.key} #{row.env} #{row.doc} #{row.label}")

    String.contains?(haystack, filter)
  end

  defp environment, do: Application.get_env(:game_server_web, :environment, :prod)

  # Never render a secret's value — only whether one is present. The page is
  # admin-only, but a config screen is exactly the kind of thing that ends up
  # in a screenshot or a screen share.
  defp display_value(%{secret: true, value: value}) when value not in [nil, ""], do: "••••••••"
  defp display_value(%{value: nil}), do: "—"
  defp display_value(%{value: ""}), do: "—"
  defp display_value(%{value: value}) when is_list(value), do: Enum.join(value, ", ")
  defp display_value(%{value: value}) when is_binary(value), do: value
  defp display_value(%{value: value}), do: inspect(value)

  defp source_badge(:config), do: {"badge-info", "config"}
  defp source_badge(:default), do: {"badge-ghost", "default"}

  defp level_badge(%{required: :prod}), do: {"badge-error", "required"}
  defp level_badge(%{required: :warn}), do: {"badge-warning", "warn"}
  defp level_badge(_row), do: nil

  defp gate_text(%{when: nil, with: []}), do: nil

  defp gate_text(row) do
    [when_text(row.when), with_text(row.with)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp when_text(nil), do: nil

  defp when_text({[group, key], value}), do: "when #{group}.#{key} is #{inspect(value)}"

  defp when_text(conditions) when is_list(conditions) do
    Enum.map_join(conditions, " and ", fn {[group, key], value} ->
      "when #{group}.#{key} is #{inspect(value)}"
    end)
  end

  defp with_text([]), do: nil
  defp with_text(siblings), do: "with #{Enum.map_join(siblings, ", ", &to_string/1)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

        <div>
          <h1 class="text-3xl font-bold">Settings</h1>
          <p class="mt-1 text-sm text-base-content/70">
            Every setting the server declares — {length(Settings.all())} across {length(@groups)} groups.
            Values resolve once at boot; change one in your config or environment and restart.
          </p>
        </div>

        <div :if={@failures != []} class="alert alert-error">
          <div>
            <h2 class="font-semibold">Missing required settings</h2>
            <ul class="list-disc list-inside text-sm">
              <li :for={failure <- @failures}>{failure}</li>
            </ul>
          </div>
        </div>

        <div :if={@warnings != []} class="alert alert-warning">
          <div>
            <h2 class="font-semibold">Half-configured ({length(@warnings)})</h2>
            <p class="text-sm">
              Some of a group's values are set and others are not. Each feature below is
              running degraded rather than as configured.
            </p>
            <ul class="list-disc list-inside text-sm">
              <li :for={warning <- @warnings}>{warning}</li>
            </ul>
          </div>
        </div>

        <div class="flex gap-3 flex-wrap items-center">
          <input
            type="text"
            value={@filter}
            phx-keyup="filter"
            phx-debounce="200"
            placeholder="Search name, variable or description…"
            class="input input-bordered flex-1 min-w-[16rem]"
          />
          <form id="settings-group-filter" phx-change="group">
            <select name="group" class="select select-bordered">
              <option value="">All groups</option>
              <option
                :for={{group, label} <- @groups}
                value={group}
                selected={@group_filter == group}
              >
                {label}
              </option>
            </select>
          </form>
        </div>

        <p :if={@rows == []} class="text-sm text-base-content/70">No settings match that filter.</p>

        <div :for={{label, rows} <- @rows} class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title text-xl">{label}</h2>
            <div class="overflow-x-auto">
              <table class="table table-zebra w-full min-w-[52rem]">
                <thead>
                  <tr>
                    <th class="w-56">Setting</th>
                    <th class="w-72">Environment variable</th>
                    <th>Value</th>
                    <th class="w-40">Source</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- rows}>
                    <td class="align-top">
                      <div class="font-mono text-sm">{row.key}</div>
                      <div :if={row.doc != ""} class="text-xs text-base-content/70 mt-1">
                        {row.doc}
                      </div>
                      <div :if={gate_text(row)} class="text-xs text-base-content/50 mt-1 italic">
                        {gate_text(row)}
                      </div>
                    </td>
                    <td class="align-top">
                      <div class="font-mono text-xs break-all">{row.env}</div>
                    </td>
                    <td class="align-top">
                      <span class="font-mono text-sm break-all">{display_value(row)}</span>
                      <span :if={row.secret} class="badge badge-ghost badge-sm ml-2">secret</span>
                      <div :if={row.source == :config} class="text-xs text-base-content/50 mt-1">
                        default: {inspect(row.default)}
                      </div>
                    </td>
                    <td class="align-top">
                      <% {class, text} = source_badge(row.source) %>
                      <span class={"badge #{class}"}>{text}</span>
                      <% level = level_badge(row) %>
                      <span :if={level} class={"badge #{elem(level, 0)} ml-1"}>
                        {elem(level, 1)}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
