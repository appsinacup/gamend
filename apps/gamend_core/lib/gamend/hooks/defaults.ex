defmodule Gamend.Hooks.Defaults do
  @moduledoc false

  # What `use Gamend.Hooks` injects into a hooks module: `@behaviour
  # Gamend.Hooks`, a default for every callback, all overridable.
  #
  # The one copy: `mix gen.sdk` writes this file into the SDK
  # (sdk/lib/gamend/hooks/defaults.ex), whose `use Gamend.Hooks` calls it too,
  # so a plugin behaves the same whether Mix builds it against the SDK or the
  # engine builds it in-process (`Gamend.Hooks.PluginBuilder.InProcess`).
  #
  # Quoted code split across three attributes: one quote block this long is
  # past credo's LongQuoteBlocks, and a function holding one counts every
  # branch of the code it quotes.

  default_callbacks =
    quote do
      @impl true
      def after_startup, do: :ok

      @impl true
      def before_stop, do: :ok

      @impl true
      def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

      @impl true
      def after_user_register(_user), do: :ok

      @impl true
      def after_user_logged_in(_user), do: :ok

      @impl true
      def after_user_updated(_user), do: :ok

      @impl true
      def after_user_online(_user), do: :ok

      @impl true
      def after_user_offline(_user), do: :ok

      @impl true
      def after_user_deleted(_user), do: :ok

      @impl true
      def after_wallet_changed(_change), do: :ok

      @impl true
      def after_inventory_changed(_change), do: :ok

      @impl true
      def before_user_register(_user, attrs), do: {:ok, attrs}

      @impl true
      def before_user_update(_user, attrs), do: {:ok, attrs}

      @impl true
      def validate_username(_username), do: :default

      @impl true
      def before_lobby_create(attrs), do: {:ok, attrs}

      @impl true
      def after_lobby_create(_lobby), do: :ok

      @impl true
      def before_lobby_join(user, lobby, opts), do: {:ok, {user, lobby, opts}}

      @impl true
      def before_group_create(_user, attrs), do: {:ok, attrs}

      @impl true
      def before_group_join(user, group, opts), do: {:ok, {user, group, opts}}

      @impl true
      def after_group_create(_group), do: :ok

      @impl true
      def before_group_update(_group, attrs), do: {:ok, attrs}

      @impl true
      def after_group_updated(_group), do: :ok

      @impl true
      def after_group_join(_user_id, _group), do: :ok

      @impl true
      def after_group_leave(_user_id, _group_id), do: :ok

      @impl true
      def after_group_deleted(_group), do: :ok

      @impl true
      def after_group_kick(_admin_id, _target_id, _group_id), do: :ok

      @impl true
      def before_group_delete(group), do: {:ok, group}

      @impl true
      def before_group_kick(admin_id, target_id, group_id),
        do: {:ok, {admin_id, target_id, group_id}}

      @impl true
      def before_party_join(user, party), do: {:ok, {user, party}}

      @impl true
      def before_party_kick(admin, target, party),
        do: {:ok, {admin, target, party}}

      @impl true
      def before_purchase(_user, product), do: {:ok, product}

      @impl true
      def after_purchase_fulfilled(_purchase), do: :ok

      @impl true
      def after_purchase_revoked(_purchase), do: :ok

      @impl true
      def after_entitlement_changed(_entitlement), do: :ok

      @impl true
      def after_score_submitted(_record), do: :ok

      @impl true
      def before_party_create(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_party_create(_party), do: :ok

      @impl true
      def before_party_update(_party, attrs), do: {:ok, attrs}

      @impl true
      def after_party_updated(_party), do: :ok

      @impl true
      def after_party_join(_user, _party), do: :ok

      @impl true
      def after_party_leave(_user, _party_id), do: :ok
    end

  @default_callbacks default_callbacks

  more_default_callbacks =
    quote do
      @impl true
      def after_party_kick(_target, _leader, _party), do: :ok

      @impl true
      def after_party_disband(_party), do: :ok

      @impl true
      def before_quest_claim(_user_id, _quest, _progress), do: :ok

      @impl true
      def after_quest_completed(_progress), do: :ok

      @impl true
      def after_quest_claimed(_progress), do: :ok

      @impl true
      def after_lobby_join(_user, _lobby), do: :ok

      @impl true
      def before_chat_message(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_chat_message(_message), do: :ok

      @impl true
      def after_chat_message_reported(_report), do: :ok

      @impl true
      def before_report_create(attrs), do: {:ok, attrs}

      @impl true
      def after_report_created(_report), do: :ok

      @impl true
      def after_report_resolved(_report), do: :ok

      @impl true
      def after_user_muted(_mute), do: :ok

      @impl true
      def before_push_send(_user_id, message), do: {:ok, message}

      @impl true
      def after_push_sent(_user_id, _message, _result), do: :ok

      @impl true
      def before_lobby_leave(user, lobby), do: {:ok, {user, lobby}}

      @impl true
      def after_lobby_leave(_user, _lobby), do: :ok

      @impl true
      def before_lobby_update(_lobby, attrs), do: {:ok, attrs}

      @impl true
      def after_lobby_updated(_lobby), do: :ok

      @impl true
      def before_lobby_delete(lobby), do: {:ok, lobby}

      @impl true
      def after_lobby_deleted(_lobby), do: :ok

      @impl true
      def before_lobby_state_change(_lobby, _from, _to), do: :ok

      @impl true
      def after_lobby_state_changed(_lobby, _from, _to), do: :ok

      @impl true
      def before_lobby_kick(host, target, lobby),
        do: {:ok, {host, target, lobby}}

      @impl true
      def after_lobby_kick(_host, _target, _lobby), do: :ok

      @impl true
      def after_lobby_host_change(_lobby, _new_host_id), do: :ok

      @impl true
      def before_ready_check_open(_subject, _user_ids), do: :ok

      @impl true
      def after_ready_check_passed(_check), do: :ok

      @impl true
      def after_ready_check_failed(_check, _reason, _not_ready), do: :ok

      @impl true
      def before_kv_get(_key, _opts), do: :public

      @impl true
      def before_matchmaking_join(_user, attrs), do: {:ok, attrs}

      @impl true
      def after_matchmaking_join(_user, _ticket), do: :ok

      @impl true
      def after_matchmaking_cancel(_user_id, _count), do: :ok

      @impl true
      def matchmaking_form_matches(_params, _tickets), do: :default

      @impl true
      def after_matchmaking_matched(_tickets, _lobby_id), do: :ok

      @impl true
      def before_tournament_register(_user, tournament),
        do: {:ok, tournament}

      @impl true
      def after_tournament_register(_user, _tournament), do: :ok

      @impl true
      def before_tournament_leave(_user, tournament), do: {:ok, tournament}

      @impl true
      def tournament_match_ready(_match), do: :ok

      @impl true
      def tournament_match_expired(_match), do: :ok

      @impl true
      def before_tournament_result(_match, winner), do: {:ok, winner}

      @impl true
      def after_tournament_match_resolved(_match), do: :ok

      @impl true
      def after_tournament_finished(_tournament, _standings), do: :ok
    end

  @more_default_callbacks more_default_callbacks

  overridable_callbacks =
    quote do
      defoverridable after_startup: 0,
                     before_stop: 0,
                     before_group_delete: 1,
                     before_group_kick: 3,
                     before_party_join: 2,
                     before_party_kick: 3,
                     before_purchase: 2,
                     after_purchase_fulfilled: 1,
                     after_purchase_revoked: 1,
                     after_entitlement_changed: 1,
                     after_score_submitted: 1,
                     before_user_register: 2,
                     after_user_register: 1,
                     after_user_logged_in: 1,
                     after_user_updated: 1,
                     after_user_online: 1,
                     after_user_offline: 1,
                     after_user_deleted: 1,
                     after_wallet_changed: 1,
                     after_inventory_changed: 1,
                     before_user_update: 2,
                     validate_username: 1,
                     on_custom_hook: 2,
                     before_lobby_create: 1,
                     after_lobby_create: 1,
                     before_group_create: 2,
                     before_group_join: 3,
                     after_group_create: 1,
                     before_group_update: 2,
                     after_group_updated: 1,
                     after_group_join: 2,
                     after_group_leave: 2,
                     after_group_deleted: 1,
                     after_group_kick: 3,
                     before_party_create: 2,
                     after_party_create: 1,
                     before_party_update: 2,
                     after_party_updated: 1,
                     after_party_join: 2,
                     after_party_leave: 2,
                     after_party_kick: 3,
                     after_party_disband: 1,
                     before_quest_claim: 3,
                     after_quest_completed: 1,
                     after_quest_claimed: 1,
                     before_lobby_join: 3,
                     after_lobby_join: 2,
                     before_chat_message: 2,
                     after_chat_message: 1,
                     after_chat_message_reported: 1,
                     before_report_create: 1,
                     after_report_created: 1,
                     after_report_resolved: 1,
                     after_user_muted: 1,
                     before_push_send: 2,
                     after_push_sent: 3,
                     before_lobby_leave: 2,
                     after_lobby_leave: 2,
                     before_lobby_update: 2,
                     after_lobby_updated: 1,
                     before_lobby_delete: 1,
                     after_lobby_deleted: 1,
                     before_lobby_state_change: 3,
                     after_lobby_state_changed: 3,
                     before_lobby_kick: 3,
                     after_lobby_kick: 3,
                     after_lobby_host_change: 2,
                     before_ready_check_open: 2,
                     after_ready_check_passed: 1,
                     after_ready_check_failed: 3,
                     before_kv_get: 2,
                     before_matchmaking_join: 2,
                     after_matchmaking_join: 2,
                     after_matchmaking_cancel: 2,
                     matchmaking_form_matches: 2,
                     after_matchmaking_matched: 2,
                     before_tournament_register: 2,
                     after_tournament_register: 2,
                     before_tournament_leave: 2,
                     tournament_match_ready: 1,
                     tournament_match_expired: 1,
                     before_tournament_result: 2,
                     after_tournament_match_resolved: 1,
                     after_tournament_finished: 2
    end

  @overridable_callbacks overridable_callbacks

  @doc false
  @spec quoted() :: Macro.t()
  def quoted do
    quote do
      @behaviour Gamend.Hooks

      unquote(@default_callbacks)
      unquote(@more_default_callbacks)
      unquote(@overridable_callbacks)
    end
  end
end
