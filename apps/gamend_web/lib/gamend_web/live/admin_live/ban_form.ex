defmodule GamendWeb.AdminLive.BanForm do
  @moduledoc """
  The admin console's ban form, shared by `/admin/bans`, the user editor on
  `/admin/users`, the rate-limiting page and the chat report queue: how long
  (a `Shared.duration_options/0` preset, or a number of days), why, for a chat
  ban its reach and the notice to the player, and the call that places it
  (`Gamend.Bans`).
  """
  use GamendWeb, :html

  alias Gamend.Bans
  alias Gamend.Bans.Ban
  alias Gamend.Chat.Moderation.Notices
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.Plugs.IpBan

  require Gamend.Bans.BanScope, as: BanScope

  @max_days 3650

  @doc "A blank form: a week, no reason."
  @spec empty() :: map()
  def empty, do: %{"duration" => "7d", "days" => "", "reason" => ""}

  attr :form, :map, required: true

  @doc "The duration, days and reason fields, for inside a `<form>`."
  def fields(assigns) do
    ~H"""
    <div>
      <label class="label text-xs">Duration</label>
      <select name="duration" class="select select-bordered select-sm">
        <option
          :for={{value, label} <- Shared.duration_options()}
          value={value}
          selected={@form["duration"] == value}
        >
          {label}
        </option>
      </select>
    </div>
    <div>
      <label class="label text-xs">Or days</label>
      <input
        type="number"
        name="days"
        min="1"
        max={max_days()}
        value={@form["days"]}
        placeholder="e.g. 3"
        class="input input-bordered input-sm w-24"
      />
    </div>
    <div class="grow">
      <label class="label text-xs">Reason (the player sees it)</label>
      <input
        type="text"
        name="reason"
        value={@form["reason"]}
        maxlength={Gamend.Limits.get(:max_ban_reason)}
        class="input input-bordered input-sm w-full"
      />
    </div>
    """
  end

  attr :form, :map, required: true

  @doc """
  A chat ban's reach (`scope`, and `scope_ref_id` for a room) and the notice
  the player is sent (`notify`, `message`), for inside a `<form>`.
  """
  def chat_fields(assigns) do
    ~H"""
    <div>
      <label class="label text-xs">Scope</label>
      <select name="scope" class="select select-bordered select-sm">
        <option :for={scope <- Ban.scopes()} value={scope} selected={@form["scope"] == scope}>
          {scope}
        </option>
      </select>
    </div>
    <div :if={@form["scope"] not in [nil, "global"]}>
      <label class="label text-xs">Lobby / group / party id</label>
      <input
        type="text"
        name="scope_ref_id"
        value={@form["scope_ref_id"]}
        class="input input-bordered input-sm w-72 font-mono"
      />
    </div>
    <div class="w-full">
      <label class="label cursor-pointer justify-start gap-2 text-xs">
        <input type="hidden" name="notify" value="false" />
        <input
          type="checkbox"
          name="notify"
          value="true"
          checked={@form["notify"] == "true"}
          class="checkbox checkbox-sm"
        /> Notify the player
      </label>
      <textarea
        name="message"
        rows="2"
        placeholder="Leave empty for the default notice"
        class="textarea textarea-bordered textarea-sm w-full"
      ><%= @form["message"] %></textarea>
    </div>
    """
  end

  @doc "The chat fields' blank values: global, notify with the default notice."
  @spec chat_defaults() :: map()
  def chat_defaults,
    do: %{"scope" => BanScope.global(), "scope_ref_id" => "", "notify" => "true", "message" => ""}

  @doc "The longest custom ban, in days."
  @spec max_days() :: pos_integer()
  def max_days, do: @max_days

  @doc """
  Places the ban the form describes on `target` (a user id for `:account` and
  `:chat`, an address for `:ip`), as `admin_id`. Days, when given, win over the
  preset. A chat ban takes its reach from the form, and sends the player the
  notice when `notify` is on.
  """
  @spec place(:ip | :account | :chat, String.t(), map(), String.t() | nil) ::
          {:ok, Bans.Ban.t()} | {:error, String.t()}
  def place(kind, target, form, admin_id) do
    with {:ok, expires_at} <- expires_at(form) do
      opts = [
        expires_at: expires_at,
        reason: Gamend.Parse.blank_to_nil(String.trim(form["reason"] || "")),
        by: admin_id
      ]

      result =
        case kind do
          :ip -> IpBan.ban(target, opts)
          :account -> Bans.ban(:account, target, opts)
          :chat -> Bans.ban(:chat, target, chat_reach(form) ++ opts)
        end

      case result do
        {:ok, ban} -> notify(ban, form)
        {:error, changeset} -> {:error, Shared.error_summary(changeset)}
      end
    end
  end

  # A room id left in the field when the scope went back to global is not part
  # of the ban.
  defp chat_reach(form) do
    case form["scope"] || BanScope.global() do
      BanScope.global() ->
        [scope: BanScope.global(), scope_ref_id: nil]

      scope ->
        [
          scope: scope,
          scope_ref_id: Gamend.Parse.blank_to_nil(String.trim(form["scope_ref_id"] || ""))
        ]
    end
  end

  # A muted player hears of it in their notifications when the moderator says
  # so, in the moderator's words or the default ones.
  defp notify(%Ban{kind: :chat} = ban, %{"notify" => "true"} = form) do
    message =
      Gamend.Parse.blank_to_nil(String.trim(form["message"] || "")) ||
        Notices.default_mute_message(ban)

    Notices.notify_muted(ban.user_id, message)
    {:ok, ban}
  end

  defp notify(ban, _form), do: {:ok, ban}

  defp expires_at(form) do
    case String.trim(form["days"] || "") do
      "" ->
        {:ok, Shared.expires_at(form["duration"])}

      days ->
        case Integer.parse(days) do
          {n, ""} when n in 1..@max_days ->
            {:ok, DateTime.add(DateTime.utc_now(:second), n, :day)}

          _ ->
            {:error, "Days must be a whole number from 1 to #{@max_days}"}
        end
    end
  end
end
