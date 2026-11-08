extends SceneTree

# Calls a live server through the generated addon and checks each answer
# lands in its named model class. Argument after `--`: the server URL.
#
# It signs in with a fresh device id, so the server needs device login on,
# and it writes: a user, a lobby and a party it leaves, and a group it keeps.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(result: GamendResult, label: String, model) -> Variant:
	if result.error:
		failures += 1
		print("FAIL ", label, ": ", result.error.message)
		return null
	var data = result.response.data
	if not is_instance_of(data, model):
		failures += 1
		print("FAIL ", label, ": got ", data)
		return null
	print("ok   ", label, " -> ", data.get_script().get_global_name())
	return data


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var url := args[0] if args.size() > 0 else "http://127.0.0.1:4000"
	var parts := url.split("://")
	var tls := parts[0] == "https"
	var host_port := parts[1].trim_suffix("/").split(":")
	var port := int(host_port[1]) if host_port.size() > 1 else (443 if tls else 80)

	var api := GamendApi.new(host_port[0], port, tls)
	root.add_child(api)
	await process_frame

	var device_id := "godot-check-%d-%d" % [Time.get_unix_time_from_system(), randi()]
	_expect(await api.authenticate_device_login(device_id), "device_login", GamendSessionResponse)
	if api.get_access_token() == "":
		failures += 1
		print("FAIL device_login: no token captured")

	var me = _expect(await api.users_get_current_user(), "get_current_user", GamendCurrentUserResponse)
	var user_id: String = me.data.id if me else ""

	var join := GamendQuickJoinRequest.new()
	join.title = "godot-check"
	join.max_users = 2
	var joined = _expect(await api.lobbies_quick_join(join), "quick_join", GamendLobbyResponse)
	if joined:
		var lobby: GamendLobby = joined.data
		var detail := await api.lobbies_get_lobby(lobby.id)
		if _expect(detail, "get_lobby", GamendLobbyResponse):
			var as_dict := GamendClient.lobby_to_dict(detail.response)
			if as_dict.get("id") != lobby.id or (as_dict.get("members", []) as Array).is_empty():
				failures += 1
				print("FAIL lobby_to_dict: ", as_dict)

	_expect(await api.lobbies_list_lobbies(), "list_lobbies", GamendLobbyPage)
	_expect(await api.lobbies_lobby_stats(), "lobby_stats", GamendLobbyStatsResponse)
	_expect(await api.users_search_users("godot-check"), "search_users", GamendPublicUserPage)
	_expect(await api.friends_list_friends(), "list_friends", GamendFriendPage)
	_expect(await api.friends_list_friend_requests(), "list_friend_requests", GamendFriendRequestsResponse)
	_expect(await api.friends_list_blacklisted_users(), "list_blacklisted_users", GamendUserBriefPage)

	var providers = _expect(await api.authenticate_list_auth_providers(), "list_auth_providers", GamendAuthProvidersResponse)
	if providers and not providers.__data__was__set:
		failures += 1
		print("FAIL list_auth_providers: data was dropped")

	var left := await api.lobbies_leave_lobby()
	if left.error:
		failures += 1
		print("FAIL leave_lobby: ", left.error.message)
	else:
		print("ok   leave_lobby")

	var new_group := GamendCreateGroupRequest.new()
	new_group.title = "godot-check-%d" % randi()
	var created = _expect(await api.groups_create_group(new_group), "create_group", GamendGroupResponse)
	if created:
		var group: GamendGroup = created.data
		_expect(await api.groups_get_group(group.id), "get_group", GamendGroupResponse)
		_expect(await api.groups_list_group_members(group.id), "list_group_members", GamendGroupMemberPage)
		_expect(await api.groups_list_group_invites(group.id), "list_group_invites", GamendGroupInvitePage)
		var link = _expect(await api.groups_create_group_invite_link(group.id), "create_group_invite_link", GamendGroupInviteLinkResponse)
		_expect(await api.groups_get_group_invite_link(group.id), "get_group_invite_link", GamendGroupInviteLinkResponse)
		if link:
			_expect(await api.groups_preview_group_invite_link(link.data.token), "preview_group_invite_link", GamendGroupInviteLinkPreviewResponse)
		_expect(await api.groups_delete_group_invite_link(group.id), "delete_group_invite_link", GamendOkResponse)
	_expect(await api.groups_list_groups(), "list_groups", GamendGroupPage)
	_expect(await api.groups_list_my_groups(), "list_my_groups", GamendGroupPage)

	var new_party := GamendCreatePartyRequest.new()
	new_party.max_size = 4
	var party = _expect(await api.parties_create_party(new_party), "create_party", GamendPartyResponse)
	if party and (party.data.members as Array).is_empty():
		failures += 1
		print("FAIL create_party: no members")
	_expect(await api.parties_show_party(), "show_party", GamendPartyResponse)
	_expect(await api.parties_party_stats(), "party_stats", GamendPartyStatsResponse)
	var left_party := await api.parties_leave_party()
	if left_party.error:
		failures += 1
		print("FAIL leave_party: ", left_party.error.message)
	else:
		print("ok   leave_party")

	var boards = _expect(await api.leaderboards_list_leaderboards(), "list_leaderboards", GamendLeaderboardPage)
	_expect(await api.leaderboards_resolve_slugs(["godot-check"]), "resolve_leaderboard_slugs", GamendLeaderboardsBySlugResponse)
	if boards and boards.data.size() > 0:
		var board: GamendLeaderboard = boards.data[0]
		_expect(await api.leaderboards_get_leaderboard(board.id), "get_leaderboard", GamendLeaderboardResponse)
		_expect(await api.leaderboards_list_leaderboard_records(board.id), "list_leaderboard_records", GamendLeaderboardRecordPage)
		_expect(await api.leaderboards_list_records_around_user(board.id, user_id), "list_records_around_user", GamendLeaderboardRecordPage)

	var cups = _expect(await api.tournaments_list_tournaments(), "list_tournaments", GamendTournamentPage)
	if cups and cups.data.size() > 0:
		var cup: GamendTournament = cups.data[0]
		_expect(await api.tournaments_get_tournament(cup.id), "get_tournament", GamendTournamentResponse)
		_expect(await api.tournaments_tournament_entries(cup.id), "tournament_entries", GamendTournamentEntryPage)
		_expect(await api.tournaments_tournament_bracket(cup.id), "tournament_bracket", GamendTournamentBracketPage)
		_expect(await api.tournaments_tournament_standings(cup.id), "tournament_standings", GamendTournamentStandingsResponse)

	_expect(await api.quests_my_quests(), "my_quests", GamendQuestPage)
	_expect(await api.quests_list_quests(), "list_quests", GamendQuestPage)
	_expect(await api.quests_quest_stats(), "quest_stats", GamendQuestStatsResponse)
	_expect(await api.economy_get_current_user_wallet(), "get_current_user_wallet", GamendWalletBalancesResponse)
	_expect(await api.economy_get_current_user_inventory(), "get_current_user_inventory", GamendInventoryResponse)
	_expect(await api.economy_list_current_user_ledger(), "list_current_user_ledger", GamendLedgerEntryPage)
	_expect(await api.payments_catalog(), "payments_catalog", GamendPaymentCatalogEntryPage)
	_expect(await api.payments_entitlements(), "payments_entitlements", GamendEntitlementPage)

	_expect(await api.health_index(), "health", GamendHealthResponse)
	_expect(await api.time_get_server_time(), "get_server_time", GamendServerTimeResponse)
	_expect(await api.stats_get_stats(), "get_stats", GamendServerStatsResponse)
	_expect(await api.signaling_stats(), "signaling_stats", GamendSignalingStatsResponse)
	_expect(await api.matchmaking_stats(), "matchmaking_stats", GamendMatchmakingStatsResponse)
	_expect(await api.hooks_list_hooks(), "list_hooks", GamendHookFunctionPage)
	_expect(await api.ready_checks_get_mine(), "get_my_ready_check", GamendMyReadyChecksResponse)
	_expect(await api.results_list_results(), "list_results", GamendPlayResultPage)
	_expect(await api.reports_list_report_kinds(), "list_report_kinds", GamendReportKindsResponse)

	await api.realtime_start()
	api.listen_to_user()
	await api._realtime.user_channel_joined
	_expect_ws(await api.kv_subscribe_ws("godot-check"), "kv_subscribe_ws")
	_expect_ws(await api.kv_unsubscribe_ws("godot-check"), "kv_unsubscribe_ws")
	_expect_ws(await api.results_list_ws({"page_size": 1}), "results_list_ws")

	_check_kv_row()

	print("failures=", failures)
	quit(1 if failures > 0 else 0)


func _expect_ws(result: GamendResult, label: String) -> void:
	if result.error:
		failures += 1
		print("FAIL ", label, ": ", result.error.message)
	else:
		print("ok   ", label)


# GamendClient reads a KV row out of a get_kv answer by hand. The typed model,
# a raw body and an older server's shape must all give the stored row: when
# the answer became `{data: KvEntry}` this read the entry, not the row, and
# every HTTP fetch came back empty with nothing failing.
func _check_kv_row() -> void:
	var entry := {"key": "k", "user_id": "", "lobby_id": "", "data": {"a": 1}, "metadata": {}}
	var cases := {
		"model": GamendKvEntryResponse.bzz_denormalize_single({"data": entry}),
		"raw": {"data": entry},
		"legacy": {"data": {"a": 1}},
	}
	for label in cases:
		var row: Dictionary = GamendClient._kv_row(cases[label])
		if row == {"a": 1}:
			print("ok   kv_row ", label)
		else:
			failures += 1
			print("FAIL kv_row ", label, ": got ", row)
