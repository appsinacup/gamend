defmodule GamendWeb.AdminLive.GitHub do
  @moduledoc """
  Every installation of the server's GitHub App (`Gamend.GitHub`), for an
  operator.

  What an operator needs to see here is the two things a customer cannot: an
  installation GitHub has **suspended** (every clone through it fails until
  the customer reinstates it) and one that **nothing uses any more**, which
  is a customer who left and a token this server can still mint. The second
  needs the host's count (`config :gamend_core, :github_usage`); without one
  the column is not drawn.

  Nothing here can act on GitHub's side. Suspending, reinstating and
  uninstalling are the customer's, on GitHub; this page says what happened.
  """
  use GamendWeb, :live_view

  alias Gamend.GitHub

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    rows = GitHub.list_all_installations(page: 1, page_size: @page_size)

    {:ok,
     socket
     |> assign(:page_title, "Admin · GitHub")
     |> assign(:configured?, GitHub.configured?())
     |> assign(:total, GitHub.count_all_installations())
     |> assign(:counts_uses?, Enum.any?(rows, &is_integer(&1.uses)))
     |> assign(:rows, rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <.admin_header page="/admin/github" />

        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <h2 class="card-title text-lg">GitHub installations</h2>
              <span class="text-xs text-muted">
                {@total} {if @total == 1, do: "installation", else: "installations"}
              </span>
            </div>

            <div :if={not @configured?} class="alert alert-warning">
              <span>
                The GitHub App is not configured on this server, so nobody can connect one. An operator sets <code class="text-xs">GAMEND_GITHUB_APP_ID</code>, <code class="text-xs">GAMEND_GITHUB_APP_SLUG</code>,
                <code class="text-xs">GAMEND_GITHUB_PRIVATE_KEY</code>
                and the <code class="text-xs">GAMEND_OAUTH_GITHUB_*</code>
                client pair (<code class="text-xs">mix gamend.github.app</code>
                makes the App and prints them).
              </span>
            </div>

            <p :if={@rows == []} class="text-sm text-muted">
              Nobody has connected a GitHub installation yet.
            </p>

            <div :if={@rows != []} class="overflow-x-auto">
              <table id="installations" class="table table-sm">
                <thead>
                  <tr>
                    <th>Account</th>
                    <th>Installation</th>
                    <th>Connected by</th>
                    <th>Repositories</th>
                    <th :if={@counts_uses?}>In use</th>
                    <th>Connected</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @rows} id={"installation-#{row.installation.id}"}>
                    <td>
                      <span class="font-medium">{row.installation.account_login}</span>
                      <span class="ml-1 text-xs text-muted">{row.installation.account_type}</span>
                    </td>
                    <td class="font-mono text-xs">{row.installation.installation_id}</td>
                    <td class="text-xs">
                      <div class="flex items-center gap-2">
                        <.user_avatar :if={row.user} user={row.user} class="size-6 shrink-0" />
                        {connected_by(row.user)}
                      </div>
                    </td>
                    <td class="text-xs">{row.installation.repository_selection || "—"}</td>
                    <td :if={@counts_uses?}>
                      <span class={[
                        "badge badge-sm",
                        if(row.uses == 0, do: "badge-ghost", else: "badge-primary")
                      ]}>
                        {row.uses}
                      </span>
                    </td>
                    <td class="text-xs text-muted">
                      <.timestamp at={row.installation.inserted_at} format="full" empty="—" />
                    </td>
                    <td>
                      <span :if={row.installation.suspended_at} class="badge badge-warning badge-sm">
                        suspended
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

  # A row goes with its user, so a missing one is a race with a deletion.
  defp connected_by(nil), do: "—"
  defp connected_by(user), do: user.email
end
