defmodule GameServerWeb.AdminLive.Quests do
  use GameServerWeb, :live_view

  alias GameServer.Quests
  alias GameServer.Quests.Quest

  @resets Quest.resets()
  @statuses ~w(active completed claimed)

  @impl true
  def mount(_params, _session, socket) do
    Quests.subscribe_quests()

    socket =
      socket
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:category_filter, nil)
      |> assign(:selected_quest, nil)
      |> assign(:form, nil)
      |> assign(:grant_form, nil)
      |> assign(:progress_page, 1)
      |> assign(:progress_page_size, 25)
      |> assign(:progress_filters, %{"user_id" => "", "quest_key" => "", "status" => ""})
      |> assign(:progress_reload_scheduled, false)
      |> reload_quests()
      |> reload_progress()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">&larr; Back to Admin</.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between">
              <h2 class="card-title">Quests ({@count})</h2>
              <div class="flex flex-wrap gap-2">
                <input
                  type="text"
                  name="category"
                  value={@category_filter || ""}
                  placeholder="Filter by category"
                  class="input input-sm input-bordered"
                  phx-change="filter_category"
                  phx-debounce="300"
                />
                <button phx-click="new_quest" class="btn btn-primary btn-sm">
                  + Create Quest
                </button>
              </div>
            </div>

            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[56rem]">
                <thead>
                  <tr>
                    <th>Key</th>
                    <th>Title</th>
                    <th>Reset</th>
                    <th>Category</th>
                    <th>Objectives</th>
                    <th>Rewards</th>
                    <th>Active</th>
                    <th>Funnel (act/comp/claim)</th>
                    <th>i18n</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={q <- @quests} id={"admin-quest-#{q.id}"}>
                    <td class="font-mono text-sm">{q.key}</td>
                    <td class="text-sm">{q.title}</td>
                    <td class="text-sm">
                      <span class={["badge badge-sm", reset_badge(q.reset)]}>{reset_text(q)}</span>
                      <span :if={q.hidden} class="badge badge-warning badge-sm ml-1">hidden</span>
                      <span :if={q.auto_claim} class="badge badge-ghost badge-sm ml-1">auto</span>
                      <span :if={q.prerequisite_quest_key} class="badge badge-ghost badge-sm ml-1">
                        chained
                      </span>
                      <span :if={q.starts_at || q.ends_at} class="badge badge-ghost badge-sm ml-1">
                        window
                      </span>
                    </td>
                    <td class="text-sm">{q.category}</td>
                    <td class="text-xs font-mono">{objectives_summary(q)}</td>
                    <td class="text-xs font-mono">{rewards_summary(q)}</td>
                    <td class="text-sm">
                      <%= if q.active do %>
                        <span class="badge badge-success badge-sm">Active</span>
                      <% else %>
                        <span class="badge badge-neutral badge-sm">Inactive</span>
                      <% end %>
                    </td>
                    <td class="text-xs font-mono">{funnel_summary(@funnels[q.key])}</td>
                    <td class="text-sm">
                      <div class="flex flex-wrap gap-1">
                        <button
                          phx-click="edit_quest"
                          phx-value-id={q.id}
                          class="btn btn-xs btn-outline btn-info"
                        >
                          Edit
                        </button>
                        <button
                          phx-click="grant_form"
                          phx-value-id={q.id}
                          class="btn btn-xs btn-outline btn-success"
                        >
                          Grant
                        </button>
                        <button
                          phx-click="delete_quest"
                          phx-value-id={q.id}
                          data-confirm="Delete this quest and all user progress?"
                          class="btn btn-xs btn-outline btn-error"
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <.pagination
                page={@page}
                total_pages={@total_pages}
                total_count={@count}
                page_size={@page_size}
                on_prev="prev_page"
                on_next="next_page"
                on_page_size="page_size"
              />
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">User Progress ({@progress_count})</h2>

            <form phx-change="filter_progress" class="flex flex-wrap gap-2 mt-2">
              <input
                type="text"
                name="user_id"
                value={@progress_filters["user_id"]}
                placeholder="User (id or name)"
                class="input input-sm input-bordered"
                phx-debounce="300"
              />
              <input
                type="text"
                name="quest_key"
                value={@progress_filters["quest_key"]}
                placeholder="Quest key"
                class="input input-sm input-bordered"
                phx-debounce="300"
              />
              <select class="select select-sm" name="status">
                <option value="">Any status</option>
                <option :for={s <- @statuses} value={s} selected={@progress_filters["status"] == s}>
                  {s}
                </option>
              </select>
            </form>

            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[56rem]">
                <thead>
                  <tr>
                    <th>User</th>
                    <th>Quest</th>
                    <th>Period</th>
                    <th>Progress</th>
                    <th>Status</th>
                    <th>Updated</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={p <- @progress_rows} id={"admin-qp-#{p.id}"}>
                    <td class="text-sm">{progress_user_name(p)}</td>
                    <td class="font-mono text-sm">{p.quest_key}</td>
                    <td class="font-mono text-sm">{p.period_key}</td>
                    <td class="text-xs font-mono">{Jason.encode!(p.objective_progress)}</td>
                    <td class="text-sm">
                      <span class={["badge badge-sm", status_badge(p.status)]}>{p.status}</span>
                    </td>
                    <td class="text-sm">
                      <.timestamp at={p.updated_at} />
                    </td>
                    <td class="text-sm">
                      <div class="flex flex-wrap gap-1">
                        <button
                          :if={p.status == "active"}
                          phx-click="force_complete"
                          phx-value-user={p.user_id}
                          phx-value-key={p.quest_key}
                          class="btn btn-xs btn-outline btn-success"
                        >
                          Complete
                        </button>
                        <button
                          :if={p.status == "completed"}
                          phx-click="force_claim"
                          phx-value-user={p.user_id}
                          phx-value-key={p.quest_key}
                          class="btn btn-xs btn-outline btn-success"
                        >
                          Force claim
                        </button>
                        <button
                          phx-click="reset_progress"
                          phx-value-user={p.user_id}
                          phx-value-key={p.quest_key}
                          data-confirm="Reset this user's current-period progress?"
                          class="btn btn-xs btn-outline btn-error"
                        >
                          Reset
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <.pagination
                page={@progress_page}
                total_pages={@progress_total_pages}
                total_count={@progress_count}
                page_size={@progress_page_size}
                on_prev="progress_prev_page"
                on_next="progress_next_page"
                on_page_size="progress_page_size"
              />
            </div>
          </div>
        </div>
      </div>

      <%!-- Create/Edit Quest Modal --%>
      <%= if @form do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-2xl">
            <h3 class="font-bold text-lg">
              {if @selected_quest, do: "Edit Quest", else: "Create Quest"}
            </h3>

            <.form for={@form} id="quest-form" phx-submit="save_quest">
              <%= if is_nil(@selected_quest) do %>
                <.input field={@form[:key]} type="text" label="Key (unique slug, e.g. daily_win_3)" />
              <% else %>
                <div class="form-control">
                  <label class="label"><span class="label-text">Key</span></label>
                  <input
                    type="text"
                    value={@selected_quest.key}
                    class="input input-bordered opacity-60"
                    disabled
                  />
                  <label class="label">
                    <span class="label-text-alt text-base-content/50">
                      Key cannot be changed after creation
                    </span>
                  </label>
                </div>
              <% end %>
              <.input field={@form[:title]} type="text" label="Title" />
              <.input field={@form[:description]} type="textarea" label="Description" />
              <.input field={@form[:icon_url]} type="text" label="Icon URL (optional)" />
              <.input
                field={@form[:reset]}
                type="select"
                label="Reset cycle"
                options={Enum.map(@resets, &{&1, &1})}
              />
              <.input
                field={@form[:reset_interval_days]}
                type="number"
                label="Reset interval in days (only for reset: interval — biweekly = 14)"
              />
              <.input
                field={@form[:category]}
                type="text"
                label="Category (free-form label for your UI)"
              />

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Objectives (JSON list: event, target, params)</span>
                </label>
                <textarea
                  name="objectives_json"
                  class="textarea textarea-bordered font-mono"
                  rows="3"
                ><%= @objectives_json %></textarea>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Rewards (JSON list: type, code, amount)</span>
                </label>
                <textarea
                  name="rewards_json"
                  class="textarea textarea-bordered font-mono"
                  rows="2"
                ><%= @rewards_json %></textarea>
              </div>

              <.input
                field={@form[:prerequisite_quest_key]}
                type="text"
                label="Prerequisite quest key (chains, optional)"
              />
              <.input
                field={@form[:starts_at]}
                type="utc-datetime-local"
                label="Starts at (event window)"
              />
              <.input
                field={@form[:ends_at]}
                type="utc-datetime-local"
                label="Ends at (event window)"
              />
              <.input field={@form[:sort_order]} type="number" label="Sort Order" />
              <.input
                field={@form[:hidden]}
                type="checkbox"
                label="Hidden (only shown after completion)"
              />
              <.input
                field={@form[:auto_claim]}
                type="checkbox"
                label="Auto-claim rewards on completion"
              />
              <.input field={@form[:active]} type="checkbox" label="Active" />

              <div class="form-control">
                <label class="label"><span class="label-text">Metadata (JSON)</span></label>
                <textarea
                  name="quest[metadata]"
                  class="textarea textarea-bordered"
                  rows="3"
                ><%= Jason.encode!((@selected_quest && @selected_quest.metadata) || %{}) %></textarea>
              </div>

              <div class="modal-action">
                <button type="button" phx-click="cancel_edit" class="btn">Cancel</button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Grant Quest Modal --%>
      <%= if @grant_form do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg">
              Grant: {@selected_quest && @selected_quest.title}
            </h3>
            <p class="text-sm text-base-content/60 mt-1">
              Force-completes every objective for the current period (auto-claim quests pay out immediately).
            </p>

            <.form for={@grant_form} id="grant-form" phx-submit="grant_quest">
              <.input field={@grant_form[:user_id]} type="text" label="User ID" />

              <div class="modal-action">
                <button type="button" phx-click="cancel_grant" class="btn">Cancel</button>
                <button type="submit" class="btn btn-success">Grant</button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Event Handlers — definitions
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:category_filter, if(category == "", do: nil, else: category))
     |> assign(:page, 1)
     |> reload_quests()}
  end

  def handle_event("prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(:page, max(1, socket.assigns.page - 1))
     |> reload_quests()}
  end

  def handle_event("next_page", _, socket) do
    {:noreply,
     socket
     |> assign(:page, socket.assigns.page + 1)
     |> reload_quests()}
  end

  def handle_event("page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:page_size, String.to_integer(size))
     |> assign(:page, 1)
     |> reload_quests()}
  end

  def handle_event("new_quest", _, socket) do
    changeset = Quests.change_quest(%Quest{})

    {:noreply,
     socket
     |> assign(:selected_quest, nil)
     |> assign(:objectives_json, ~s([{"event": "example_event", "target": 1, "params": {}}]))
     |> assign(:rewards_json, "[]")
     |> assign(:form, to_form(changeset, as: "quest"))}
  end

  def handle_event("edit_quest", %{"id" => id}, socket) do
    quest = Quests.get_quest(id)

    {:noreply,
     socket
     |> assign(:selected_quest, quest)
     |> assign(:objectives_json, Jason.encode!(quest.objectives))
     |> assign(:rewards_json, Jason.encode!(quest.rewards))
     |> assign(:form, to_form(Quests.change_quest(quest), as: "quest"))}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_quest, nil)
     |> assign(:form, nil)}
  end

  def handle_event("save_quest", %{"quest" => params} = all_params, socket) do
    params =
      params
      |> parse_metadata()
      |> put_json_list(all_params, "objectives_json", "objectives")
      |> put_json_list(all_params, "rewards_json", "rewards")

    result =
      if socket.assigns.selected_quest do
        Quests.update_quest(socket.assigns.selected_quest, params)
      else
        Quests.create_quest(params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:form, nil)
         |> assign(:selected_quest, nil)
         |> put_flash(
           :info,
           if(socket.assigns.selected_quest, do: "Quest updated", else: "Quest created")
         )
         |> reload_quests()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "quest"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save quest: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_quest", %{"id" => id}, socket) do
    case Quests.get_quest(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Quest not found")}

      quest ->
        case Quests.delete_quest(quest) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Quest deleted")
             |> reload_quests()
             |> reload_progress()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete quest")}
        end
    end
  end

  def handle_event("grant_form", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_quest, Quests.get_quest(id))
     |> assign(:grant_form, to_form(%{"user_id" => ""}, as: "grant"))}
  end

  def handle_event("cancel_grant", _, socket) do
    {:noreply,
     socket
     |> assign(:grant_form, nil)
     |> assign(:selected_quest, nil)}
  end

  def handle_event("grant_quest", %{"grant" => %{"user_id" => user_id_str}}, socket) do
    quest = socket.assigns.selected_quest

    case Ecto.UUID.cast(user_id_str) do
      {:ok, user_id} ->
        case Quests.admin_complete(user_id, quest.key) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:grant_form, nil)
             |> assign(:selected_quest, nil)
             |> put_flash(:info, "Quest granted to user #{user_id}")
             |> reload_progress()}

          {:error, :already_completed} ->
            {:noreply, put_flash(socket, :error, "User already completed this quest")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to grant quest")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid user ID")}
    end
  end

  # ---------------------------------------------------------------------------
  # Event Handlers — progress
  # ---------------------------------------------------------------------------

  def handle_event("filter_progress", params, socket) do
    filters = Map.take(params, ["user_id", "quest_key", "status"])

    {:noreply,
     socket
     |> assign(:progress_filters, Map.merge(socket.assigns.progress_filters, filters))
     |> assign(:progress_page, 1)
     |> reload_progress()}
  end

  def handle_event("progress_prev_page", _, socket) do
    {:noreply,
     socket
     |> assign(:progress_page, max(1, socket.assigns.progress_page - 1))
     |> reload_progress()}
  end

  def handle_event("progress_next_page", _, socket) do
    {:noreply,
     socket
     |> assign(:progress_page, socket.assigns.progress_page + 1)
     |> reload_progress()}
  end

  def handle_event("progress_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:progress_page_size, String.to_integer(size))
     |> assign(:progress_page, 1)
     |> reload_progress()}
  end

  def handle_event("force_complete", %{"user" => user_id, "key" => key}, socket) do
    case Quests.admin_complete(user_id, key) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Quest completed") |> reload_progress()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("force_claim", %{"user" => user_id, "key" => key}, socket) do
    case Quests.admin_claim(user_id, key) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Quest claimed") |> reload_progress()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reset_progress", %{"user" => user_id, "key" => key}, socket) do
    case Quests.admin_reset(user_id, key) do
      {:ok, :not_found} ->
        {:noreply, put_flash(socket, :error, "No current-period progress to reset")}

      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Progress reset") |> reload_progress()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:quests_changed}, socket) do
    {:noreply, reload_quests(socket)}
  end

  # Completion/claim events arrive once per player action across the whole
  # game — coalesce them so a busy hour can't turn the page into a reload loop.
  def handle_info({event, _user_id, _payload}, socket)
      when event in [:quest_progress, :quest_completed, :quest_claimed] do
    {:noreply, schedule_progress_reload(socket)}
  end

  def handle_info(:reload_progress_now, socket) do
    {:noreply,
     socket
     |> assign(:progress_reload_scheduled, false)
     |> reload_progress()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp schedule_progress_reload(socket) do
    if socket.assigns[:progress_reload_scheduled] do
      socket
    else
      Process.send_after(self(), :reload_progress_now, 1_000)
      assign(socket, :progress_reload_scheduled, true)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reload_quests(socket) do
    page = socket.assigns[:page] || 1
    page_size = socket.assigns[:page_size] || 25
    category = socket.assigns[:category_filter]

    quests = Quests.list_quests(page: page, page_size: page_size, category: category)
    count = Quests.count_quests(category: category)
    total_pages = if page_size > 0, do: div(count + page_size - 1, page_size), else: 0
    funnels = Map.new(quests, fn q -> {q.key, Quests.funnel(q.key)} end)

    socket
    |> assign(:resets, @resets)
    |> assign(:statuses, @statuses)
    |> assign(:quests, quests)
    |> assign(:funnels, funnels)
    |> assign(:count, count)
    |> assign(:total_pages, max(total_pages, 1))
  end

  defp reload_progress(socket) do
    page = socket.assigns[:progress_page] || 1
    page_size = socket.assigns[:progress_page_size] || 25
    filters = socket.assigns[:progress_filters] || %{}

    opts = [
      page: page,
      page_size: page_size,
      user_id: blank_to_nil(filters["user_id"]),
      quest_key: blank_to_nil(filters["quest_key"]),
      status: blank_to_nil(filters["status"])
    ]

    rows = Quests.list_progress(opts)
    count = Quests.count_progress(opts)
    total_pages = if page_size > 0, do: div(count + page_size - 1, page_size), else: 0

    socket
    |> assign(:progress_rows, rows)
    |> assign(:progress_count, count)
    |> assign(:progress_total_pages, max(total_pages, 1))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp progress_user_name(progress) do
    case progress.user do
      %{username: username, display_name: display_name} ->
        display_name || username || progress.user_id

      _ ->
        progress.user_id
    end
  end

  defp objectives_summary(quest) do
    Enum.map_join(quest.objectives, ", ", fn o -> "#{o.event}×#{o.target}" end)
  end

  defp rewards_summary(%Quest{rewards: []}), do: "-"

  defp rewards_summary(quest) do
    Enum.map_join(quest.rewards, ", ", fn r -> "#{r.amount} #{r.code}" end)
  end

  defp funnel_summary(nil), do: "0/0/0"

  defp funnel_summary(funnel) do
    "#{Map.get(funnel, "active", 0)}/#{Map.get(funnel, "completed", 0)}/#{Map.get(funnel, "claimed", 0)}"
  end

  defp reset_badge(reset) do
    case reset do
      "never" -> "badge-primary"
      "daily" -> "badge-info"
      "weekly" -> "badge-accent"
      "monthly" -> "badge-secondary"
      "interval" -> "badge-warning"
      _ -> "badge-ghost"
    end
  end

  defp reset_text(%{reset: "interval", reset_interval_days: days}), do: "every #{days}d"
  defp reset_text(%{reset: reset}), do: reset

  defp status_badge(status) do
    case status do
      "active" -> "badge-info"
      "completed" -> "badge-success"
      "claimed" -> "badge-neutral"
      _ -> "badge-ghost"
    end
  end

  defp parse_metadata(params) do
    case Map.get(params, "metadata") do
      nil ->
        params

      json_str when is_binary(json_str) ->
        case Jason.decode(json_str) do
          {:ok, map} when is_map(map) -> Map.put(params, "metadata", map)
          _ -> Map.delete(params, "metadata")
        end

      _ ->
        params
    end
  end

  defp put_json_list(params, all_params, source_key, target_key) do
    case Jason.decode(Map.get(all_params, source_key, "")) do
      {:ok, list} when is_list(list) -> Map.put(params, target_key, list)
      _ -> params
    end
  end
end
