defmodule GamendWeb.RedeemLive do
  @moduledoc """
  Where a player types a redemption code (`Gamend.Quests.redeem_code/2`).

  It lists what codes can finish now, like the quests page, and
  `/redeem?quest=spring_gift` narrows it to one, so an email or a community
  post can link straight to the box for that one. The link names the quest,
  never a code: a URL ends up in logs and history.

  In `live_session :current_user` because a visitor can land here from a link.
  A signed-out visitor who submits a working code gets a guest account
  (`GamendWeb.UserAuth.ensure_user/1`) and redeems on it; a code that does not
  work makes no account. The socket reconnects with that account, so its card
  reading Redeemed is what such a visitor sees, not the flash.
  """
  use GamendWeb, :live_view

  alias Gamend.AccountRequired
  alias Gamend.Accounts.Scope
  alias Gamend.Quests
  alias GamendWeb.ContentText
  alias GamendWeb.LiveHelpers
  alias GamendWeb.RateLimit
  alias GamendWeb.UserAuth

  @page_size 50

  use GamendWeb.UrlState,
    reload: :load_entries,
    keys: [:page, :quest, page_size: [min: 24]]

  @impl true
  def mount(params, _session, socket) do
    user = get_user(socket)

    if connected?(socket) do
      Quests.subscribe_quests()
      if user, do: Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Redeem a code"))
     |> assign(:locale, Gettext.get_locale(GamendWeb.Gettext))
     |> assign(:page, 1)
     |> assign(:page_size, @page_size)
     |> assign(:quest, nil)
     |> assign(:attempt, 0)
     |> assign(:connected?, connected?(socket))
     |> assign(:needs_account, false)
     |> assign_form()
     |> GamendWeb.UrlState.from_url(params)
     |> load_entries()}
  end

  @impl true
  def handle_event("redeem", %{"redeem" => %{"token" => token}}, socket) do
    case String.trim(token) do
      "" -> {:noreply, socket}
      token -> {:noreply, attempt(socket, token)}
    end
  end

  # Only after a crash between a redemption's commit and its payout: the row
  # is completed and waits, as any quest's does.
  def handle_event("claim", %{"key" => key}, socket) do
    case get_user(socket) do
      nil ->
        {:noreply, socket}

      user ->
        case Quests.claim(user.id, key) do
          {:ok, %{rewards: rewards}} ->
            {:noreply,
             socket
             |> put_flash(:info, Enum.join([gettext("Rewards claimed!") | gains(rewards)], " "))
             |> load_entries()}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not claim this quest."))}
        end
    end
  end

  def handle_event("show_all", _params, socket) do
    {:noreply, socket |> assign(:quest, nil) |> assign(:page, 1) |> load_entries()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> load_entries()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> load_entries()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size, min: 24) |> load_entries()}

  # Every quest edit anywhere is `{:quests_changed}`: one reload covers a burst.
  @impl true
  def handle_info({:quests_changed}, socket),
    do: {:noreply, LiveHelpers.reload_soon(socket, :reload_entries)}

  def handle_info({event, _payload}, socket) when event in [:quest_completed, :quest_claimed],
    do: {:noreply, LiveHelpers.reload_soon(socket, :reload_entries)}

  def handle_info(:reload_entries, socket),
    do: {:noreply, socket |> LiveHelpers.reloaded(:reload_entries) |> load_entries()}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp attempt(socket, token) do
    case get_user(socket) do
      nil -> attempt_as_visitor(socket, token)
      user -> redeem(socket, user, token)
    end
  end

  # Checked before the account is made, so a typo, a bot or a crawler makes no
  # row. Counted per address: the visitor has no account to count it on yet.
  defp attempt_as_visitor(socket, token) do
    with :ok <- RateLimit.check_redeem("ip:" <> visitor_ip(socket)),
         :ok <- open_code(token),
         :ok <- guests_may_claim(),
         {:ok, socket} <- guest(socket) do
      redeem(socket, get_user(socket), token)
    else
      {:error, reason} -> refuse(socket, reason)
    end
  end

  defp visitor_ip(socket), do: socket.assigns[:client_ip] |> to_string() |> RateLimit.ip_key()

  # A guest could not redeem here, so there is no use making one.
  defp guests_may_claim do
    if AccountRequired.required?(:quest_claims), do: {:error, :account_required}, else: :ok
  end

  defp open_code(token) do
    if Quests.code_open?(token), do: :ok, else: {:error, :code_not_found}
  end

  # Device accounts off, or the per-IP limit on new ones: this visitor has to
  # sign in another way.
  defp guest(socket) do
    case UserAuth.ensure_user(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, _reason} -> {:error, :account_required}
    end
  end

  defp redeem(socket, user, token) do
    with :ok <- RateLimit.check_redeem(user.id),
         {:ok, %{progress: progress, rewards: rewards}} <- Quests.redeem_code(user.id, token) do
      socket
      |> put_flash(:info, redeemed_flash(progress.quest_key, rewards))
      |> assign(:needs_account, false)
      |> assign(:attempt, socket.assigns.attempt + 1)
      |> assign_form()
      |> load_entries()
    else
      {:error, reason} -> refuse(socket, reason)
    end
  end

  defp refuse(socket, reason) do
    socket
    |> put_flash(:error, refusal(reason))
    |> assign(:needs_account, reason == :account_required)
  end

  defp refusal(:code_not_found), do: gettext("That code is not valid.")
  defp refusal(:already_redeemed), do: gettext("You already redeemed this.")
  defp refusal(:account_required), do: gettext("Register to redeem this code.")
  defp refusal(:redeem_rate_limit), do: gettext("Too many tries. Wait a minute.")
  defp refusal({:hook_rejected, reason}) when is_binary(reason), do: reason
  defp refusal(_reason), do: gettext("Could not redeem this code.")

  # "Code redeemed: Spring gift +100 gold". The title, so a key that pays
  # nothing still says what it opened.
  defp redeemed_flash(quest_key, rewards) do
    title =
      case Quests.get_quest_by_key(quest_key) do
        nil -> quest_key
        quest -> ContentText.t(quest.title)
      end

    Enum.join([gettext("Code redeemed: %{title}", title: title) | gains(rewards)], " ")
  end

  defp gains(rewards), do: Enum.map(rewards, &"+#{&1.amount} #{&1.code}")

  defp assign_form(socket), do: assign(socket, :form, to_form(%{"token" => ""}, as: :redeem))

  defp get_user(socket), do: Scope.user(socket.assigns[:current_scope])

  defp load_entries(socket) do
    user = get_user(socket)
    page_size = socket.assigns.page_size

    %{entries: entries, total: total} =
      Quests.redeemable(user && user.id,
        quest: socket.assigns.quest,
        page: socket.assigns.page,
        page_size: page_size
      )

    socket
    |> assign(:entries, ContentText.translate(entries))
    |> assign(:total_count, total)
    |> assign(:total_pages, max(ceil(total / page_size), 1))
    |> assign(:redeemed_count, Enum.count(entries, & &1.progress))
    |> assign(:now, DateTime.utc_now(:second))
  end

  defp register_href(locale),
    do: GamendWeb.HostLayouts.localized_href(~p"/users/register", locale)

  defp seconds_left(%{ends_at: %DateTime{} = ends_at}, now),
    do: max(DateTime.diff(ends_at, now), 0)

  defp seconds_left(_quest, _now), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- `nav_key`: a redeemed code moves the navbar's coin balance. --%>
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      nav_key={@redeemed_count}
    >
      <div class="space-y-6">
        <div data-heading-fit class="flex items-center gap-3">
          <.page_title
            icon={GamendWeb.HostLayouts.nav_icon("/redeem", "hero-ticket-solid")}
            tone={GamendWeb.HostLayouts.nav_tone("/redeem")}
          >
            {gettext("Redeem a code")}
          </.page_title>
        </div>

        <div class="card bg-base-200 max-w-narrow">
          <div class="card-body">
            <%!-- Submit only: a check on each keystroke would spend the rate
                  limit, and the token never goes in a URL. --%>
            <.form
              for={@form}
              id="redeem-form"
              phx-submit="redeem"
              class="flex flex-col gap-3 sm:flex-row sm:items-end"
            >
              <div class="grow">
                <%!-- The id moves after a success: LiveView never overwrites
                      the input that has focus, and it would keep the used code. --%>
                <.input
                  field={@form[:token]}
                  id={"redeem-token-#{@attempt}"}
                  type="text"
                  label={gettext("Code")}
                  autocomplete="off"
                  spellcheck="false"
                  required
                />
              </div>
              <%!-- Disabled until the socket is up: before that, Enter is a
                    plain GET with the code in the URL. --%>
              <button
                type="submit"
                id="redeem-submit"
                class="btn btn-primary mb-2"
                disabled={not @connected?}
              >
                <.icon name="hero-gift-solid" class="w-4 h-4" />
                {gettext("Redeem")}
              </button>
            </.form>
            <a
              :if={@needs_account}
              id="redeem-register"
              href={register_href(@locale)}
              class="btn btn-sm btn-surface w-fit"
            >
              <.icon name="hero-user-plus-solid" class="w-4 h-4" />
              {gettext("Register")}
            </a>
          </div>
        </div>

        <button
          :if={@quest}
          type="button"
          id="redeem-show-all"
          phx-click="show_all"
          class="btn btn-sm btn-surface"
        >
          <.icon name="hero-squares-2x2-solid" class="size-4" />
          {gettext("All")}
        </button>

        <div
          :if={@entries != []}
          id="redeem-list"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
        >
          <.redeem_card :for={entry <- @entries} entry={entry} now={@now} />
        </div>

        <div :if={@total_pages > 1} class="flex justify-center items-center pt-4">
          <.pagination
            page={@page}
            total_pages={@total_pages}
            total_count={@total_count}
            page_size={@page_size}
            on_prev="prev_page"
            on_next="next_page"
            on_page_size="page_size"
            page_sizes={[24, 50, 100, 200]}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :entry, :map, required: true
  attr :now, DateTime, required: true

  defp redeem_card(assigns) do
    assigns =
      assigns
      |> assign(:quest, assigns.entry.quest)
      |> assign(:left, seconds_left(assigns.entry.quest, assigns.now))

    ~H"""
    <.entity_card
      id={"redeem-card-#{@quest.key}"}
      title={@quest.title}
      icon_url={@quest.icon_url}
      type={:quest}
      tone={GamendWeb.HostLayouts.nav_tone("/redeem")}
      description={@quest.description}
      class={@entry.progress && "border border-success/30"}
    >
      <:badges>
        <span :if={@entry.progress} class="badge badge-success text-nowrap">
          {gettext("Redeemed")}
        </span>
        <span :if={@quest.category} class="badge badge-ghost badge-sm text-nowrap">
          {@quest.category}
        </span>
      </:badges>

      <div :if={@quest.rewards != []} class="flex flex-wrap items-center gap-1">
        <.reward_chip
          :for={reward <- @quest.rewards}
          type={reward.type}
          code={reward.code}
          amount={reward.amount}
          name={(@quest.metadata || %{})["reward_names"][reward.code]}
        />
      </div>

      <div :if={@left && is_nil(@entry.progress)} class="flex items-center gap-1.5 text-muted">
        <.icon name="hero-clock-solid" class="w-3.5 h-3.5" />
        <span class="text-xs">
          {gettext("Ends in %{time}", time: GamendWeb.QuestsLive.format_duration(@left))}
        </span>
      </div>

      <button
        :if={@entry.claimable}
        phx-click="claim"
        phx-value-key={@quest.key}
        class="btn btn-success btn-sm w-full mt-3"
      >
        <.icon name="hero-gift-solid" class="w-4 h-4" />
        {gettext("Claim")}
      </button>
    </.entity_card>
    """
  end
end
