defmodule GameServer.Modules.ExampleHook do
  @moduledoc """
  Example hooks implementation shipped as an OTP plugin.

  This is intentionally kept out of the default plugins directory so it does not
  affect test runs or production deployments.

  To try it locally:

      export GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples

  Then restart the server and use the Admin Config page to reload plugins.
  """

  # `use` (not `@behaviour`) so the SDK supplies overridable defaults for every
  # callback — this example only defines the ones it demonstrates. Any callback
  # left out simply keeps its default behaviour.
  use GameServer.Hooks
  require Logger

  alias GameServer.Accounts
  alias GameServer.Economy
  alias GameServer.Groups
  alias GameServer.Hooks
  alias GameServer.Inventory
  alias GameServer.KV
  alias GameServer.Leaderboards
  alias GameServer.Lock
  alias GameServer.Notifications
  alias GameServer.Payments
  alias GameServer.Tournaments

  # Sample content this plugin owns. Both are namespaced so the hooks below can
  # ignore leaderboards/tournaments belonging to the rest of the game.
  @login_leaderboard "example_login_count"
  @tournament_slug "example-weekly-cup"
  @quest_prefix "example_"
  @group_title "Example Guild"
  @group_icon "/icons/user-group.svg"

  # Icons are URLs into the server's own typed icon set (`GET /icons/<name>.svg`,
  # the heroicons the UI already ships), so a sample needs no hosted artwork and
  # renders in the reader's theme. A game with its own art uploads it instead —
  # see the two-step icon upload in the admin API — and stores that URL here.
  @welcome_kv_key "example_welcome"

  @impl true
  def after_startup do
    Logger.info("[ExampleHook] after_startup called")

    # Every sample is created only when missing, so restarts and plugin
    # reloads are safe.
    ensure_login_leaderboard()
    ensure_weekly_cup()
    ensure_quests()
    ensure_welcome_kv()
    ensure_group()
    ensure_store_products()

    [
      %{
        hook: "custom_hello",
        meta: %{
          description: "Example dynamic hook that returns hello",
          args: [%{name: "name", type: "string"}],
          example_args: ["Dragos"]
        }
      }
    ]
  end

  # ── Sample leaderboard: how many times each player has logged in ──────────
  #
  # The `incr` operator makes every submission add to the stored score, so the
  # login hook can just submit 1 without reading the previous value.

  defp ensure_login_leaderboard do
    case Leaderboards.get_active_leaderboard_by_slug(@login_leaderboard) do
      nil ->
        Leaderboards.create_leaderboard(%{
          slug: @login_leaderboard,
          title: "Logins",
          icon_url: "/icons/chart-bar.svg",
          description: "How many times each player has logged in.",
          sort_order: :desc,
          operator: :incr
        })

      existing ->
        sync_icon(existing, "/icons/chart-bar.svg", &Leaderboards.update_leaderboard/2)
    end
  end

  # Only the icon is reconciled on entities that outlive a deploy: their title
  # and schedule belong to whatever the server (or an admin) has done with them
  # since. Quests are different — they are pure definitions, so they are synced
  # whole.
  defp sync_icon(entity, icon, update) do
    if Map.get(entity, :icon_url) != icon, do: update.(entity, %{icon_url: icon})
    :ok
  end

  @impl true
  def after_user_logged_in(user) do
    pay_subscription_stipend(user)

    case Leaderboards.get_active_leaderboard_by_slug(@login_leaderboard) do
      nil -> :ok
      board -> Leaderboards.submit_score(board.id, user.id, 1)
    end

    :ok
  end

  # Category is a theme ("Check-ins", "Events"), not a cadence — the reset
  # field already says daily/weekly/monthly, and the page shows it as its own
  # badge. Using the cadence as the category rendered every label twice.
  # ── Sample quests ─────────────────────────────────────────────────────────
  # The core wires the "login" event into the quest engine, so no unlock call
  # is needed anywhere — defining a quest is enough. Every one below tracks
  # logins so they all make visible progress from a single action.

  # One quest of every shape the engine supports, so a fresh deployment shows
  # the whole feature surface rather than a single row: each reset cycle, plus
  # the orthogonal flags (auto-claim, chained, hidden, time-windowed).
  #
  # `category` is a free-form display label, so it is written the way it should
  # read on the page. It used to be passed as `kind:`, which is not a Quest
  # field — the changeset dropped it silently and every quest here was created
  # with no category at all.
  defp ensure_quests do
    now = DateTime.utc_now(:second)

    [
      %{
        key: "first_login",
        icon_url: "/icons/hand-raised.svg",
        title: "Welcome aboard",
        description: "Log in for the first time.",
        category: "Achievements",
        reset: "never",
        auto_claim: true,
        objectives: [%{event: "login", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 100}]
      },
      %{
        key: "daily_login",
        icon_url: "/icons/calendar-days.svg",
        title: "Daily check-in",
        description: "Log in today.",
        category: "Check-ins",
        reset: "daily",
        objectives: [%{event: "login", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 25}]
      },
      %{
        key: "weekly_regular",
        icon_url: "/icons/calendar.svg",
        title: "Weekly regular",
        description: "Log in on five different days this week.",
        category: "Check-ins",
        reset: "weekly",
        objectives: [%{event: "login", target: 5}],
        rewards: [
          %{type: "currency", code: "gold", amount: 150},
          %{type: "currency", code: "gems", amount: 5}
        ]
      },
      %{
        key: "monthly_devotee",
        icon_url: "/icons/calendar-date-range.svg",
        title: "Monthly devotee",
        description: "Log in twenty times this month.",
        category: "Check-ins",
        reset: "monthly",
        objectives: [%{event: "login", target: 20}],
        rewards: [%{type: "currency", code: "gems", amount: 25}]
      },
      # `interval` restarts a fixed number of days after each completion,
      # rather than on a calendar boundary.
      %{
        key: "recurring_visit",
        icon_url: "/icons/arrow-path.svg",
        title: "Stop by again",
        description: "Log in. Becomes available again three days later.",
        category: "Check-ins",
        reset: "interval",
        reset_interval_days: 3,
        objectives: [%{event: "login", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 40}]
      },
      # Chained: stays locked until its prerequisite is completed.
      %{
        key: "loyal_veteran",
        icon_url: "/icons/shield-check.svg",
        title: "Loyal veteran",
        description: "Log in fifty times, once you have said hello.",
        category: "Achievements",
        reset: "never",
        prerequisite_quest_key: @quest_prefix <> "first_login",
        objectives: [%{event: "login", target: 50}],
        rewards: [%{type: "item", code: "veteran_banner", amount: 1}]
      },
      # Hidden quests stay a teaser in the catalog until they are earned.
      %{
        key: "night_owl",
        icon_url: "/icons/moon.svg",
        title: "Night owl",
        description: "Some things are found rather than announced.",
        category: "Secrets",
        reset: "never",
        hidden: true,
        objectives: [%{event: "login", target: 100}],
        rewards: [%{type: "item", code: "lantern", amount: 1}]
      },
      # A window is orthogonal to the reset cycle: this is a daily that only
      # runs while the event is on.
      %{
        key: "launch_festival",
        icon_url: "/icons/sparkles.svg",
        title: "Launch festival",
        description: "A daily that only counts while the festival is running.",
        category: "Events",
        reset: "daily",
        starts_at: DateTime.add(now, -1, :day),
        ends_at: DateTime.add(now, 30, :day),
        objectives: [%{event: "login", target: 1}],
        rewards: [%{type: "currency", code: "gold", amount: 75}]
      }
    ]
    |> Enum.each(fn attrs ->
      key = @quest_prefix <> attrs.key

      attrs = Map.put(attrs, :key, key)

      # Reconciled on every boot rather than only created: these quests are
      # *defined* here, so editing one (a new icon, a reworded description) has
      # to reach the rows a previous deploy already made.
      case GameServer.Quests.get_quest_by_key(key) do
        nil -> GameServer.Quests.create_quest(attrs)
        quest -> GameServer.Quests.update_quest(quest, Map.delete(attrs, :key))
      end
    end)

    :ok
  end

  # ── Sample store products ─────────────────────────────────────────────────
  #
  # Enough to see the store page do something: one product per kind. Payment
  # providers are not involved here — `grant_config` is free-form, and the
  # payout below is what turns a fulfilled purchase into currency or an item.

  @products [
    %{
      sku: "example_gold_pouch",
      title: "Pouch of Gold",
      description: "500 gold, delivered straight to your wallet.",
      kind: "consumable",
      grant_config: %{"currency" => "gold", "amount" => 500}
    },
    %{
      sku: "example_gem_bag",
      title: "Bag of Gems",
      description: "25 gems for the impatient adventurer.",
      kind: "consumable",
      grant_config: %{"currency" => "gems", "amount" => 25}
    },
    %{
      sku: "example_starter_pack",
      title: "Starter Pack",
      description: "A one-off bundle: gold, gems and a commemorative compass.",
      kind: "consumable",
      grant_config: %{
        "currency" => "gold",
        "amount" => 1000,
        "items" => [%{"item" => "compass", "qty" => 1}]
      }
    },
    %{
      sku: "example_supporter_badge",
      title: "Supporter Badge",
      description: "Permanent badge on your profile. Thanks for keeping the lights on.",
      kind: "entitlement",
      grant_config: %{"entitlement_key" => "supporter"}
    },
    %{
      sku: "example_monthly_pass",
      title: "Monthly Pass",
      description: "Daily bonus gold and a supporter badge, renewed monthly.",
      kind: "subscription",
      grant_config: %{"entitlement_key" => "monthly_pass", "duration_days" => 30}
    }
  ]

  defp ensure_store_products do
    Enum.each(@products, fn attrs ->
      # Reconciled, like the quests: editing a price or blurb here has to reach
      # the row a previous deploy already made.
      case Payments.get_product_by_sku(attrs.sku) do
        nil -> Payments.create_product(attrs)
        product -> Payments.update_product(product, Map.delete(attrs, :sku))
      end
    end)

    :ok
  end

  # What a completed purchase actually pays out. Core marks the purchase
  # fulfilled and records the entitlement; turning `grant_config` into game
  # currency or items is the game's job, which is this.
  @impl true
  def after_purchase_fulfilled(purchase) do
    case Payments.get_product(purchase.product_id) do
      nil ->
        :ok

      product ->
        config = product.grant_config
        qty = max(purchase.quantity || 1, 1)

        grant_currency(purchase.user_id, config, qty, product.sku)
        grant_items(purchase.user_id, config, qty)
    end

    :ok
  end

  defp grant_currency(user_id, %{"currency" => code, "amount" => amount}, qty, sku)
       when is_binary(code) and is_integer(amount) and amount > 0 do
    # The purchase id would be the natural idempotency key; the sku keeps this
    # example short and is enough for a sample store.
    Economy.grant(user_id, code, amount * qty, reason: "store:" <> sku)
  end

  defp grant_currency(_user_id, _config, _qty, _sku), do: :ok

  defp grant_items(user_id, %{"items" => items}, qty) when is_list(items) do
    Enum.each(items, fn
      %{"item" => item, "qty" => item_qty} when is_binary(item) and is_integer(item_qty) ->
        Inventory.grant_item(user_id, item, item_qty * qty, reason: "store_purchase")

      _ ->
        :ok
    end)
  end

  defp grant_items(_user_id, _config, _qty), do: :ok

  # ── Sample KV entry: a global value any client can read ───────────────────

  defp ensure_welcome_kv do
    case KV.get(@welcome_kv_key) do
      {:ok, _entry} -> :ok
      _missing -> KV.put(@welcome_kv_key, %{"message" => "Hello from ExampleHook!"})
    end

    :ok
  end

  # ── Sample group ──────────────────────────────────────────────────────────
  #
  # A group needs a creator, so unlike the other samples this one cannot be
  # made out of nothing at boot. It is seeded with the oldest account when one
  # exists, and otherwise by the first player to register — so an instance ends
  # up with one of every entity either way.

  defp ensure_group do
    case List.first(Accounts.list_all_users(%{}, page_size: 1, sort_dir: "asc")) do
      nil -> :ok
      owner -> ensure_group(owner)
    end
  end

  defp ensure_group(user) do
    case Groups.get_group_by_title(@group_title) do
      nil ->
        Groups.create_group(user.id, %{
          title: @group_title,
          icon_url: @group_icon,
          description: "A public group created by the example plugin.",
          type: "public"
        })

      existing ->
        # Players can rename a group they belong to, so only the icon is synced.
        sync_icon(existing, @group_icon, fn group, attrs ->
          Groups.update_group(user.id, group.id, attrs)
        end)
    end

    :ok
  end

  @impl true
  def after_user_register(user) do
    ensure_group(user)
    grant_starter_kit(user)
    welcome_notification(user)
    :ok
  end

  # Everyone starts with something, so a brand-new account has a wallet and an
  # inventory worth looking at instead of two empty pages. Idempotent: the key
  # is the user, so re-running this never double-grants.
  @starter_currency [{"gold", 250}, {"gems", 10}]
  @starter_items [{"compass", 1}, {"spyglass", 1}, {"rations", 3}]

  defp grant_starter_kit(user) do
    for {code, amount} <- @starter_currency do
      Economy.grant(user.id, code, amount,
        reason: "starter_kit",
        idempotency_key: "starter:#{user.id}:#{code}"
      )
    end

    for {item, qty} <- @starter_items do
      Inventory.grant_item(user.id, item, qty,
        reason: "starter_kit",
        idempotency_key: "starter:#{user.id}:#{item}"
      )
    end

    :ok
  end

  # What the Monthly Pass actually buys: a gold stipend once per day, paid on
  # the day's first login. The idempotency key is the date, so logging in ten
  # times pays once — and a lapsed subscription simply stops matching.
  @pass_entitlement "monthly_pass"
  @pass_daily_gold 100

  defp pay_subscription_stipend(user) do
    if Payments.has_entitlement?(user.id, @pass_entitlement) do
      today = Date.utc_today() |> Date.to_iso8601()

      Economy.grant(user.id, "gold", @pass_daily_gold,
        reason: "monthly_pass_daily",
        idempotency_key: "pass:#{user.id}:#{today}"
      )
    end

    :ok
  end

  # Sent once per player rather than on every login. `admin_create_notification/3`
  # is the plugin-side entry point: unlike `send_notification/2` it doesn't
  # require the sender and recipient to be friends, so a plugin can post
  # system messages (here the player is both sender and recipient).
  defp welcome_notification(user) do
    Notifications.admin_create_notification(user.id, user.id, %{
      "title" => "Welcome!",
      "content" => "Thanks for joining. Register for the Weekly Cup to get started.",
      "icon_url" => "/icons/bell.svg",
      "metadata" => %{"type" => "example_welcome"}
    })

    :ok
  end

  # ── Sample tournament: a weekly cup that plays itself ─────────────────────
  #
  # Registration is the only thing players do. `recur` makes the server create
  # next week's occurrence automatically when this one finishes.

  defp ensure_weekly_cup do
    case Tournaments.get_tournament_by_slug(@tournament_slug) do
      nil ->
        Tournaments.create_tournament(%{
          slug: @tournament_slug,
          title: "Weekly Cup",
          icon_url: "/icons/trophy.svg",
          description: "Register any time; the bracket is drawn every Monday.",
          starts_at: next_monday(),
          recur: "0 0 * * 1",
          bracket_size: 8,
          round_window_sec: 24 * 3600
        })

      existing ->
        sync_icon(existing, "/icons/trophy.svg", &Tournaments.update_tournament/2)
    end
  end

  defp next_monday do
    today = Date.utc_today()
    days = rem(8 - Date.day_of_week(today), 7)
    days = if days == 0, do: 7, else: days

    DateTime.new!(Date.add(today, days), ~T[00:00:00], "Etc/UTC")
  end

  # A real game would start a lobby here and report the outcome later. This
  # sample decides immediately, so resolving one match readies the next and the
  # whole bracket plays itself out.
  @impl true
  def tournament_match_ready(match) do
    if match.tournament.slug == @tournament_slug do
      winner = Enum.random(Enum.reject([match.a_entry_id, match.b_entry_id], &is_nil/1))
      resolve_with_retry(match.id, winner, 3)
    end

    :ok
  end

  # Every match in a round becomes ready at once, so these hooks run
  # concurrently. SQLite (the default dev adapter) rejects a second concurrent
  # write transaction with "Database busy" immediately — WAL mode cannot queue
  # writers — so the write is retried. Postgres writes distinct rows and does
  # not hit this.
  defp resolve_with_retry(match_id, winner, attempts) do
    Tournaments.resolve_match(match_id, winner)
    :ok
  rescue
    error ->
      if attempts > 1 do
        Process.sleep(150)
        resolve_with_retry(match_id, winner, attempts - 1)
      else
        Logger.warning(
          "[ExampleHook] could not resolve match #{match_id}: #{Exception.message(error)}"
        )

        :ok
      end
  end

  @impl true
  def after_tournament_finished(tournament, standings) do
    if tournament.slug == @tournament_slug do
      champions = Enum.map_join(standings.champions, ", ", & &1.leader_id)
      Logger.info("[ExampleHook] #{tournament.title} finished, champions: #{champions}")

      Enum.each(standings.champions, fn entry ->
        Notifications.admin_create_notification(entry.leader_id, entry.leader_id, %{
          "title" => "You won the #{tournament.title}!",
          "content" => "Congratulations — you took the whole bracket.",
          "metadata" => %{"type" => "example_tournament_won", "tournament_id" => tournament.id}
        })
      end)
    end

    :ok
  end

  @impl true
  def on_custom_hook("custom_hello", [name]) when is_binary(name), do: "hello #{name}"

  def on_custom_hook("custom_hello", _args), do: "hello"

  @impl true
  def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

  @doc """
  Notification codes this plugin sends. Core rejects any notification whose
  metadata "type" is not declared here or by core, so a client never receives
  a code nobody documented.
  """
  def notification_types do
    %{
      "example_quest_completed" => "The player finished an example quest",
      "example_rival_online" => "A rival the player follows came online"
    }
  end

  @doc """
  Realtime events this plugin pushes with `GameServer.Realtime.push_to_user/3`.
  They ride the player's existing user:<id> channel, so the client needs no new
  subscription — it just listens for these names.
  """
  def realtime_events do
    %{
      "example_quest_progress" => "An objective counter moved",
      "example_boss_spawned" => "A world boss spawned near the player"
    }
  end

  @doc """
  Environment variables this plugin reads. Declaration only — it makes them
  visible on the admin runtime page next to the server's own.
  """
  def env_vars do
    [
      %{
        name: "EXAMPLE_HOOK_DIFFICULTY",
        default: "normal",
        description: "Difficulty band the example quests use"
      },
      # The type is inferred from the default, so Config.get/1 returns an
      # integer here and a boolean below — no :type key needed.
      %{
        name: "EXAMPLE_HOOK_MAX_BOTS",
        default: 8,
        description: "Bots added to a match when it is short-handed"
      },
      %{
        name: "EXAMPLE_HOOK_TUTORIAL",
        default: true,
        description: "Show the tutorial to new players"
      }
    ]
  end

  @doc """
  KV data schema example: entries under the "pb_loadout" key are pushed as
  compact binary (KvEntry data_pb) on protobuf sockets. Exact keys or
  "prefix*" patterns are supported.
  """
  def kv_schemas do
    %{"pb_loadout" => ExampleHook.V1.ExampleLoadout}
  end

  # --- Matchmaking ----------------------------------------------------------
  #
  # `match_params` are always strings on the wire (they are the bucket key, and
  # buckets have to compare byte-for-byte). Anything numeric is therefore
  # stringified on the way in and parsed back in the matcher — the two hooks
  # below show both halves of that.

  @doc """
  Server authority over the queue.

  The client asks for a mode; the server decides everything that must not be
  client-controlled. Here the skill rating is read server-side and written into
  the ticket as a *coarse bucket* (a string, so equal buckets queue together),
  while the exact rating rides along as a string for the matcher to parse.

  Returning `{:error, reason}` refuses the join outright.
  """
  @impl true
  def before_matchmaking_join(user, attrs) do
    params = Map.get(attrs, "match_params", %{})
    mode = Map.get(params, "mode", "casual")

    if mode in ~w(casual ranked) do
      rating = server_rating(user)

      # match_params IS the bucket key: tickets only meet when it matches
      # byte-for-byte. So it may hold coarse, string dimensions only — putting
      # the exact rating here would give every player their own bucket. The
      # precise number stays on the user record for the matcher to read.
      {:ok,
       Map.put(attrs, "match_params", %{
         "mode" => mode,
         "band" => Integer.to_string(div(rating, 500))
       })}
    else
      {:error, :unknown_mode}
    end
  end

  @doc """
  Custom matcher for one bucket (all tickets here share identical params).

  Called once per bucket per sweep, in-process — so an O(n^2) scan is fine;
  this one is O(n log n). Ranked play reads each player's exact integer rating
  (from the user record — `match_params` only carries the coarse band), pairs
  the closest two, and refuses pairs further apart than a window that widens
  the longer someone has waited. Casual falls through to `:default`, the
  built-in FIFO matcher.

  Core re-checks the block list on whatever is returned, so a bug here can
  never seat players who blocked each other.
  """
  @impl true
  def matchmaking_form_matches(%{"mode" => "ranked"}, tickets) do
    tickets
    |> Enum.map(&{server_rating(&1.user), &1})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.chunk_every(2, 2, :discard)
    |> Enum.filter(fn [{rating_a, a}, {rating_b, b}] ->
      abs(rating_a - rating_b) <= max(window(a), window(b))
    end)
    |> Enum.map(fn [{_, a}, {_, b}] -> [a, b] end)
  end

  def matchmaking_form_matches(_params, _tickets), do: :default

  @doc "Log the pairing so the example server shows matchmaking working."
  @impl true
  def after_matchmaking_matched(tickets, lobby_id) do
    names = Enum.map_join(tickets, " vs ", & &1.user_id)
    Logger.info("[ExampleHook] match ready in lobby #{lobby_id}: #{names}")
  end

  # Rating tolerance grows by 100 for every 5s spent queueing, so nobody waits
  # forever just because their rating is unusual.
  defp window(ticket) do
    waited_ms = DateTime.diff(DateTime.utc_now(), ticket.queued_at, :millisecond)
    100 + div(waited_ms, 5_000) * 100
  end

  defp server_rating(user) do
    # A real game would read this from its own store; the point is that it is
    # server-side, not whatever the client claimed.
    case user.metadata do
      %{"rating" => rating} when is_integer(rating) -> rating
      %{"rating" => rating} when is_binary(rating) -> parse_int(rating, 1000)
      _ -> 1000
    end
  end

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  @doc """
  Typed protobuf hook example (see proto/example_hook.proto).

  The HelloProtoRequest/HelloProtoReply message pair registers this hook's
  schema by name, so the server converts at the boundary: protobuf clients
  call it with encoded bytes (`args_raw`), JSON clients with a plain object
  (`{"name": "x", "repeat": 2}`) — this function always receives the
  decoded request struct and returns a reply struct.
  """
  def hello_proto(%ExampleHook.V1.HelloProtoRequest{} = req) do
    repeat = max(req.repeat, 1)
    greeting = String.duplicate("Hello, #{req.name}! ", repeat) |> String.trim_trailing()

    %ExampleHook.V1.HelloProtoReply{
      greeting: greeting,
      name_length: byte_size(req.name)
    }
  end

  @doc "Say hi to a user"
  def hello(name) when is_binary(name) do
    # Exercise an external dependency so the bundle task can prove it ships deps.
    Bunt.ANSI.format(["Hello1, ", name, "!"], false)
  end

  @doc "Return an updated metadata map for the current caller"
  def set_current_user_meta(key, value) when is_binary(key) do
    do_set_user_meta(Hooks.caller_user(), key, value)
  end

  defp do_set_user_meta(user, key, value) do
    meta = user.metadata || %{}
    meta = Map.put(meta, key, value)
    {:ok, updated_user} = Accounts.update_user(user, %{metadata: meta})
    updated_user
  end

  # ── Benchmark RPCs ──────────────────────────────────────────────────

  @doc "Benchmark: instant return, no I/O. Measures pure RPC overhead."
  def bench_noop, do: :ok

  @doc "Benchmark: read a KV entry from the database."
  def bench_kv_read(key) when is_binary(key) do
    case KV.get(key) do
      {:ok, entry} -> entry.value
      _ -> nil
    end
  end

  @doc "Benchmark: read from ETS (in-memory). Measures RPC + ETS overhead."
  def bench_memory_read(key) when is_binary(key) do
    case :ets.lookup(:game_server_bench, key) do
      [{^key, val}] -> val
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Benchmark: write to KV inside an advisory lock."
  def bench_kv_write_locked(key) when is_binary(key) do
    resource_id = :erlang.phash2(key)

    _result =
      Lock.serialize("bench", resource_id, fn ->
        ts = System.system_time(:millisecond)
        KV.put(key, %{"ts" => ts, "writer" => "bench"})
      end)

    :ok
  end

  @doc "Benchmark: ensure the ETS table + seed key exist, then read a KV entry."
  def bench_setup(key) when is_binary(key) do
    # Create ETS table for memory benchmarks (idempotent)
    try do
      :ets.new(:game_server_bench, [:named_table, :public, :set])
    rescue
      ArgumentError -> :already_exists
    end

    :ets.insert(:game_server_bench, {key, %{"seeded" => true}})

    # Seed a KV entry for DB read benchmarks
    KV.put(key, %{"seeded" => true})
    :ok
  end
end
