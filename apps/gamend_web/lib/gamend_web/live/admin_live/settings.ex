defmodule GamendWeb.AdminLive.Settings do
  @moduledoc """
  Every declared setting, grouped, with its effective value and where that
  value came from.

  Read-only by design. Settings resolve once at boot — most of them configure
  things Phoenix, Ecto and Nebulex read a single time — so an editable field
  here would promise a change it could not deliver. What this page does
  guarantee is that the list is complete: it renders `Gamend.Settings.all/0`,
  the same declaration that generates `.env.example` and derives every
  environment variable name — every one of them, without exception — and the
  variables loaded plugins declare (`Gamend.Hooks.Declarations`).

  The page masks secrets; the `.env` it posts for does not
  (`GamendWeb.AdminSettingsController`), since that file is for restoring a
  server.

  Variables that other software reads (`RELEASE_COOKIE`, `FLY_REGION`) are not
  settings and are deliberately absent; `/admin/system` reports those.
  """

  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Settings
  alias GamendWeb.RuntimeIntrospection, as: Introspection

  require GamendWeb.UrlParam, as: UrlParam

  use GamendWeb.UrlState,
    reload: :assign_rows,
    keys: [:filter, :changed_only, group_filter: [param: UrlParam.group(), type: :atom]]

  @required "required"
  @default "default"

  @impl true
  def mount(params, _session, socket) do
    {failures, warnings} = Settings.validate(environment())

    {:ok,
     socket
     |> assign(:filter, "")
     |> assign(:group_filter, nil)
     |> assign(:changed_only, false)
     |> assign(:failures, failures)
     |> assign(:warnings, warnings)
     |> assign(:groups, groups())
     |> assign(:has_password?, has_password?(socket.assigns.current_scope))
     |> GamendWeb.UrlState.from_url(params)
     |> assign_rows()}
  end

  defp groups, do: Settings.groups() ++ plugin_groups(Introspection.plugin_env_vars())

  # Whether the download asks for a password: only of an account that has one.
  defp has_password?(scope) do
    case Scope.user(scope) do
      %User{} = user -> Accounts.has_password?(user)
      _none -> false
    end
  end

  defp plugin_groups([]), do: []
  defp plugin_groups(_vars), do: [{Introspection.plugin_env_group(), "Plugin variables"}]

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

  def handle_event("toggle_changed", _params, socket) do
    {:noreply, socket |> update(:changed_only, &(not &1)) |> assign_rows()}
  end

  defp assign_rows(socket) do
    filter = String.downcase(socket.assigns.filter)
    %{group_filter: group_filter, changed_only: changed_only} = socket.assigns

    rows =
      (Enum.map(Settings.all(), &Settings.describe/1) ++ Introspection.plugin_env_vars())
      |> Enum.filter(fn row ->
        (is_nil(group_filter) or row.group == group_filter) and matches?(row, filter) and
          (not changed_only or changed?(row))
      end)
      |> Enum.group_by(& &1.label)
      |> Enum.sort_by(&elem(&1, 0))

    assign(socket, :rows, rows)
  end

  defp changed?(row), do: row.value != row.default

  # One card's rows under their `section` headings; a group with none is one
  # unnamed run.
  defp sections(rows), do: rows |> Enum.group_by(& &1.section) |> Enum.sort_by(&elem(&1, 0))

  defp matches?(_row, ""), do: true

  defp matches?(row, filter) do
    haystack =
      String.downcase("#{row.key} #{row.env} #{row.doc} #{row.label}")

    String.contains?(haystack, filter)
  end

  defp environment, do: Application.get_env(:gamend_web, :environment, :prod)

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
  defp source_badge(:default), do: {"badge-ghost", @default}

  defp level_badge(%{required: :prod}), do: {"badge-error", @required}
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
        <.admin_header page="/admin/settings">
          <:subtitle>
            Every setting the server declares — {length(Settings.all())} across {length(@groups)} groups.
            Values resolve once at boot; change one in your config or environment and restart.
            The download holds real secrets.
          </:subtitle>
          <:actions>
            <%!-- A plain POST, not a LiveView event: the answer is a file. It
                  asks for the password again (`AdminSettingsController`);
                  an account with none signed in recently, which is enough. --%>
            <.form
              for={%{}}
              as={:export}
              id="settings-export"
              action={~p"/admin/settings/export"}
              method="post"
              class="flex flex-wrap items-center gap-2"
            >
              <input
                :if={@has_password?}
                type="password"
                name="password"
                id="settings-export-password"
                required
                autocomplete="current-password"
                placeholder="Your password"
                aria-label="Your password, to download the .env"
                class="input input-sm w-44"
              />
              <button type="submit" class="btn btn-sm btn-outline">
                <.icon name="hero-arrow-down-tray-solid" class="w-4 h-4" /> Download .env
              </button>
            </.form>
          </:actions>
        </.admin_header>

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
            <h2 class="font-semibold">Incomplete configuration ({length(@warnings)})</h2>
            <p class="text-sm">
              Each setting below is unset while something needs it: a feature it belongs
              to is switched on or partly configured, so that feature runs degraded or not
              at all. Outside production this list also names what production will refuse
              to boot without.
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
          <form id="settings-group-filter" phx-change="group" phx-no-unused-field>
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
          <label class="label cursor-pointer gap-2 text-sm">
            <input
              id="settings-changed-only"
              type="checkbox"
              class="checkbox checkbox-sm"
              checked={@changed_only}
              phx-click="toggle_changed"
            /> Changed from default
          </label>
        </div>

        <p :if={@rows == []} class="text-sm text-muted">No settings match that filter.</p>

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
                <tbody :for={{section, section_rows} <- sections(rows)}>
                  <tr :if={section}>
                    <th colspan="4" scope="colgroup" class="bg-base-200 text-sm font-semibold">
                      {section}
                    </th>
                  </tr>
                  <tr :for={row <- section_rows}>
                    <td class="align-top">
                      <div class="font-mono text-sm">{row.key}</div>
                      <div :if={row.doc != ""} class="text-xs text-muted mt-1">
                        {row.doc}
                      </div>
                      <div :if={gate_text(row)} class="text-xs text-muted mt-1 italic">
                        {gate_text(row)}
                      </div>
                    </td>
                    <td class="align-top">
                      <div class="font-mono text-xs break-all">{row.env}</div>
                    </td>
                    <td class="align-top">
                      <span class="font-mono text-sm break-all">{display_value(row)}</span>
                      <span :if={row.secret} class="badge badge-ghost badge-sm ml-2">secret</span>
                      <div :if={row.source == :config} class="text-xs text-muted mt-1">
                        default: {inspect(row.default)}
                      </div>
                    </td>
                    <td class="align-top">
                      <% {class, text} = source_badge(row.source) %>
                      <span class={"badge #{class}"}>{text}</span>
                      <span :if={changed?(row)} class="badge badge-warning ml-1">changed</span>
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
