defmodule GameServer.Limits do
  @moduledoc """
  Central module for configurable validation limits.

  All limits have sensible defaults and can be overridden at boot time via
  `config :game_server_core, GameServer.Limits, key: value` or at runtime
  via `Application.put_env(:game_server_core, GameServer.Limits, [...])`.

  ## Environment variables

  Each limit can be set via an environment variable. The env var name maps to
  the limit key with an uppercase `LIMIT_` prefix, e.g.:

      LIMIT_MAX_METADATA_SIZE=32768   -> :max_metadata_size
      LIMIT_MAX_PAGE_SIZE=100         -> :max_page_size

  Env vars are read once at boot in `config/runtime.exs`.

  ## Usage in schemas

      import GameServer.Limits, only: [get: 1, validate_metadata_size: 2]

      changeset
      |> validate_length(:title, max: GameServer.Limits.get(:max_group_title))
      |> validate_metadata_size(:metadata)

  ## Usage in controllers

      page_size = GameServer.Limits.clamp_page_size(params["page_size"])
  """

  # Every limit is an optional integer with a compiled default; the `LIMIT_`
  # env prefix predates the naming convention and is pinned here so the
  # documented names keep working.
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :limits,
    label: "Limits"

  # ── Global ──────────────────────────────────────────────
  setting(:max_metadata_size, :integer, default: 16_384)
  setting(:max_page_size, :integer, default: 100)

  setting(:max_upload_bytes, :integer,
    default: 5_242_880,
    doc: "Max size of a single uploaded object (avatars/UGC). 5 MiB."
  )

  # ── User ────────────────────────────────────────────────
  setting(:max_display_name, :integer, default: 80)
  setting(:min_username, :integer, default: 3)
  setting(:max_username, :integer, default: 32)

  setting(:max_sockets_per_user, :integer,
    default: 20,
    doc: "Concurrent sockets per user. 0 disables; counted per app instance."
  )

  setting(:max_email, :integer, default: 160)
  setting(:max_profile_url, :integer, default: 512)
  setting(:max_device_id, :integer, default: 256)

  # ── Groups ──────────────────────────────────────────────
  setting(:max_group_title, :integer, default: 80)
  setting(:max_group_description, :integer, default: 500)
  setting(:max_group_members, :integer, default: 10_000)
  setting(:max_groups_per_user, :integer, default: 50)
  setting(:max_groups_created_per_user, :integer, default: 20)
  setting(:max_group_pending_invites, :integer, default: 100)

  # ── Lobbies ─────────────────────────────────────────────
  setting(:max_lobby_title, :integer, default: 80)
  setting(:max_lobby_users, :integer, default: 128)
  setting(:max_lobby_password, :integer, default: 128)

  # ── Parties ─────────────────────────────────────────────
  setting(:max_party_size, :integer, default: 32)
  setting(:max_party_pending_invites, :integer, default: 20)

  # ── Chat ────────────────────────────────────────────────
  setting(:max_chat_content, :integer, default: 4_096)

  setting(:max_chat_messages_per_day, :integer,
    default: 5_000,
    doc: "Rolling 24h; 0 disables. Needs rate limiting on; ETS backend counts per instance."
  )

  # ── Notifications ───────────────────────────────────────
  setting(:max_notification_title, :integer, default: 255)
  setting(:max_notification_content, :integer, default: 10_000)
  setting(:max_notifications_per_user, :integer, default: 500)

  # ── Push ────────────────────────────────────────────────
  setting(:max_push_tokens_per_user, :integer,
    default: 20,
    doc: "Live (non-disabled) device tokens per user."
  )

  # Byte caps (not characters): FCM and APNs limit the wire payload to 4096
  # bytes, so only byte caps can guarantee deliverability.
  setting(:max_push_title, :integer, default: 255)
  setting(:max_push_body, :integer, default: 4_000)

  setting(:max_push_data_size, :integer,
    default: 4_096,
    doc: "Serialized byte size of a push message's custom data map."
  )

  # ── Friends ─────────────────────────────────────────────
  setting(:max_friends_per_user, :integer, default: 500)
  setting(:max_pending_friend_requests, :integer, default: 100)

  # ── Hooks ───────────────────────────────────────────────
  setting(:max_hook_args_size, :integer, default: 65_536)
  setting(:max_hook_args_count, :integer, default: 32)

  # ── KV ──────────────────────────────────────────────────
  setting(:max_kv_key, :integer, default: 512)
  setting(:max_kv_value_size, :integer, default: 65_536)
  setting(:max_kv_entries_per_user, :integer, default: 1_000)

  # ── Leaderboards ────────────────────────────────────────
  setting(:max_leaderboard_title, :integer, default: 255)
  setting(:max_leaderboard_description, :integer, default: 1_000)
  setting(:max_leaderboard_slug, :integer, default: 100)

  # ── Tournaments ─────────────────────────────────────────
  setting(:max_tournament_title, :integer, default: 255)
  setting(:max_tournament_description, :integer, default: 1_000)
  setting(:max_tournament_slug, :integer, default: 100)

  setting(:max_tournament_entries, :integer,
    default: 10_000,
    doc: "Hard cap on a tournament's own max_entries setting."
  )

  setting(:max_tournament_bracket_size, :integer, default: 256)

  # ── Quests ──────────────────────────────────────────────
  setting(:max_quests, :integer, default: 500)
  setting(:max_quest_key, :integer, default: 100)
  setting(:max_quest_title, :integer, default: 255)
  setting(:max_quest_category, :integer, default: 64)
  setting(:max_quest_description, :integer, default: 1_000)
  setting(:max_objectives_per_quest, :integer, default: 10)
  setting(:max_quest_reward_entries, :integer, default: 10)

  setting(:max_active_quests_per_user, :integer,
    default: 200,
    doc: "Progress rows a user may hold in the current periods; excess events are ignored."
  )

  setting(:max_quest_period_history, :integer,
    default: 90,
    doc: "Days of daily/weekly period history kept before the retention prune."
  )

  # ── Matchmaking ─────────────────────────────────────────
  setting(:max_matchmaking_players, :integer,
    default: 64,
    doc: "Hard cap on a ticket's own max_players setting."
  )

  setting(:max_matchmaking_params_size, :integer,
    default: 2_048,
    doc: "Serialized byte size of a ticket's match_params map."
  )

  setting(:matchmaking_timeout_ms, :integer,
    default: 30_000,
    doc: "How long the oldest ticket waits before a below-max group still forms."
  )

  setting(:matchmaking_tick_ms, :integer,
    default: 3_000,
    doc: "Sweep interval of the matchmaking worker."
  )

  setting(:matchmaking_offline_grace_ms, :integer,
    default: 300_000,
    doc:
      "Grace before an offline player's ticket is pruned; long enough that a brief disconnect keeps its queue position."
  )

  # ── Ready checks ────────────────────────────────────────
  setting(:ready_check_timeout_ms, :integer,
    default: 15_000,
    doc: "Default answering window. Overridable per check by the caller."
  )

  setting(:max_ready_check_participants, :integer,
    default: 64,
    doc: "Hard cap on participants in one check."
  )

  @doc """
  Returns a map of all limit keys and their current effective values.
  """
  @spec all() :: map()
  def all, do: Map.new(__settings__(), &{&1.key, GameServer.Settings.get(__MODULE__, &1.key)})

  @doc """
  Returns the current value for the given limit key.

  Reads from `Application.get_env(:game_server_core, GameServer.Limits)` first,
  falling back to the compiled default.
  """
  @spec get(atom()) :: integer() | any()
  def get(key) when is_atom(key), do: GameServer.Settings.get(__MODULE__, key)

  @doc """
  Returns the compiled defaults map. Useful for the admin UI to display
  defaults vs. overrides.
  """
  @spec defaults() :: map()
  def defaults, do: Map.new(__settings__(), &{&1.key, &1.default})

  @doc """
  Clamps a raw page_size parameter to [1, max_page_size].
  Accepts nil, string, or integer. Returns integer.
  """
  @spec clamp_page_size(any(), integer()) :: integer()
  def clamp_page_size(raw, default \\ 25) do
    parsed =
      case raw do
        nil ->
          default

        val when is_integer(val) ->
          val

        val when is_binary(val) ->
          case Integer.parse(val) do
            {n, _} -> n
            :error -> default
          end

        _ ->
          default
      end

    max(1, min(parsed, get(:max_page_size)))
  end

  @doc """
  Clamps a raw page parameter to [1, ∞). Same parsing logic as page_size.
  """
  @spec clamp_page(any()) :: pos_integer()
  def clamp_page(raw) do
    parsed =
      case raw do
        nil ->
          1

        val when is_integer(val) ->
          val

        val when is_binary(val) ->
          case Integer.parse(val) do
            {n, _} -> n
            :error -> 1
          end

        _ ->
          1
      end

    max(1, parsed)
  end

  # ── Ecto Changeset Helpers ──────────────────────────────────

  @doc """
  Validates that a `:map` field, when serialized to JSON, does not exceed
  `max_metadata_size` bytes. Add this to any changeset that casts a metadata
  or arbitrary JSON map field.

      changeset
      |> validate_metadata_size(:metadata)
      |> validate_metadata_size(:value, :max_kv_value_size)
  """
  @spec validate_metadata_size(Ecto.Changeset.t(), atom(), atom()) :: Ecto.Changeset.t()
  def validate_metadata_size(changeset, field, limit_key \\ :max_metadata_size) do
    import Ecto.Changeset, only: [get_change: 2, add_error: 3]

    case get_change(changeset, field) do
      nil ->
        changeset

      value when is_map(value) ->
        max = get(limit_key)

        case Jason.encode(value) do
          {:ok, json} when byte_size(json) > max ->
            add_error(changeset, field, "is too large (max #{max} bytes)")

          _ ->
            changeset
        end

      _other ->
        changeset
    end
  end
end
