class_name GamendLogs
extends Node

## Ships client log entries to the server, where they land in the same log
## stream as the server's own lines.
##
## [b]Usage[/b] — add as a child of whatever owns the Gamend client, then:
## [codeblock]
## var sink := GamendLogs.new()
## add_child(sink)
## sink.setup("https://your.host", func(): return gamend_api.get_access_token())
## DebugLog.log_added.connect(sink.submit)
## [/codeblock]
##
## Read [member session_id] and send it as the [code]x-gamend-session[/code]
## header on your API calls and as a [code]client_session[/code] socket connect
## param. That is what makes a search for one id return the client's lines and
## the server lines logged while serving that client, interleaved.
##
## [b]Why plain HTTPRequest and not the generated API client[/b]
##
## Because this has to work when the rest of the client does not. It uploads at
## boot before anything is configured or authenticated, it retries while the
## socket is down, and it flushes a previous run's leftovers before the SDK
## exists. A sink that needs a healthy client to report an unhealthy one is a
## sink that goes quiet exactly when it matters.
##
## [b]Crash survival[/b]
##
## The in-memory buffer dies with the process, and a crash is the case worth
## having logs for. So pending entries are mirrored to [code]user://[/code] as
## they arrive and uploaded on the next launch. Set
## [code]logging/file_logging/enable_file_logging[/code] in project settings and
## the engine's own [code]godot.log[/code] — the one with the stack trace — gets
## picked up on the next boot too.

## Emitted after each upload attempt. `ok` is false on any transport or server
## error; `dropped` is the server's running count of entries it knows were lost.
signal flushed(ok: bool, accepted: int, dropped: int)

const _POLICY_PATH := "/api/v1/client_logs/policy"
const _INGEST_PATH := "/api/v1/client_logs"

## Where the pending buffer is mirrored, so a crash does not take the evidence
## with it. Read and cleared on the next launch.
const _SPOOL_PATH := "user://gamend_client_logs.ndjson"

## Godot's own log, if file logging is enabled. Shipped once per launch,
## tail-first, because that is where an engine-level crash leaves its trace.
const _ENGINE_LOG_PATH := "user://logs/godot.log"
const _ENGINE_LOG_TAIL_LINES := 200

## Level ordering for the server-supplied floor. Anything below the floor is
## discarded on the device, so verbosity costs nothing when it is off.
const _RANK := {"trace": 0, "debug": 1, "info": 2, "warn": 3, "error": 4, "off": 99}

## Flush when either trips. An error flushes immediately regardless: the entry
## most likely to be followed by a crash is the one least worth buffering.
@export var flush_interval_sec := 10.0
@export var flush_at_entries := 50

## Hard ceiling on what is held between flushes. Beyond this the oldest go, and
## the gap in the sequence numbers tells the server it happened — a lossy
## session that reports itself as lossy is recoverable; one that looks quiet is
## not.
@export var max_buffered := 500

## Unique per run, generated locally. Never persisted: a reused id would merge
## two runs into one timeline, and the server binds an id to its first owner.
var session_id := ""

var _base_url := ""
var _token_provider: Callable = Callable()
var _pending: Array[Dictionary] = []
var _in_flight := false
var _seq := 0
var _elapsed := 0.0
var _http: HTTPRequest
var _spool: FileAccess
var _started := false
var _recovered: Array = []
var _engine_tail: Array = []
var _meta: Dictionary = {}
## Set once the server has accepted a batch, after which the run's
## description no longer needs to ride along on every upload.
var _session_registered := false
var _started_at := 0.0

## Server policy. Collect nothing until it has been fetched — a client that
## guesses is a client that uploads what the operator did not ask for.
var _enabled := false
var _level := "info"
var _category_levels := {}
var _batch_max := 200


# The id is generated here, not in setup(): a caller needs it to stamp the API
# header before the sink is configured, and `_ready` does not fire for a node
# constructed outside the tree.
func _init() -> void:
	session_id = _new_session_id()
	_started_at = Time.get_unix_time_from_system()


func _ready() -> void:
	set_process(false)
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	# setup() is routinely called from a parent's _init(), before either node is
	# in the tree — and HTTPRequest refuses to send from outside it. So the
	# first request waits for here rather than failing silently at boot, which
	# is the one moment the sink most needs to work.
	if _started:
		_fetch_policy()


## [param base_url] is the scheme+host+port of the server, e.g.
## `https://game.example.com`. [param token_provider] is optional and may
## return an empty string; entries sent without a token are recorded
## anonymously and adopted once the same run signs in.
func setup(base_url: String, token_provider: Callable = Callable()) -> void:
	_base_url = base_url.rstrip("/")
	_token_provider = token_provider
	# Read the previous run's leftovers first. `submit()` opens the spool for
	# WRITE, which truncates it — so anything that logged before this point
	# would otherwise erase the crash it was meant to explain.
	_recovered = _read_spool()
	_engine_tail = _read_engine_log_tail()
	_started = true
	set_process(true)
	if is_inside_tree():
		_fetch_policy()


func _process(delta: float) -> void:
	if not _enabled:
		return
	_elapsed += delta
	if _elapsed >= flush_interval_sec:
		_elapsed = 0.0
		flush()


## Buffer one entry. Connect this to `DebugLog.log_added`.
##
## Safe to call before [method setup]: entries are held and gated once the
## policy arrives, so nothing logged during boot is lost just for being early.
func submit(entry: Dictionary) -> void:
	if not _should_collect(entry):
		return
	_seq += 1
	var record := {
		"seq": _seq,
		"at": float(entry.get("time", Time.get_unix_time_from_system())),
		"level": _wire_level(entry.get("severity", 2)),
		"category": str(entry.get("category", "general")),
		"message": str(entry.get("message", "")),
		"lobby_id": str(entry.get("lobby_id", "")),
		"screen": str(entry.get("screen", "")),
	}
	# Collapse an immediate repeat instead of sending it again. A stuck retry
	# loop or a per-frame warning is the shape that actually fills a log store,
	# and "×140" carries the same information as 140 identical lines for the
	# cost of one. Only against the tail, so ordering is never disturbed.
	if not _pending.is_empty():
		var last: Dictionary = _pending[-1]
		if (
			last.message == record.message
			and last.level == record.level
			and last.category == record.category
			and last.lobby_id == record.lobby_id
		):
			last["repeat"] = int(last.get("repeat", 1)) + 1
			last["at"] = record.at
			_spool_rewrite()
			return

	_pending.append(record)
	_spool_write(record)

	# Trim from the front: the newest entries are the ones nearest the failure.
	while _pending.size() > max_buffered:
		_pending.pop_front()

	if record.level == "error" or _pending.size() >= flush_at_entries:
		flush()


## Upload everything buffered. A no-op while a flush is already in flight —
## batches are ordered by sequence, and overlapping uploads would interleave.
func flush() -> void:
	if _in_flight or _pending.is_empty() or not _enabled or _base_url.is_empty():
		return
	if _http == null or not is_inside_tree():
		return
	_in_flight = true
	var batch := _pending.slice(0, _batch_max)
	_pending = _pending.slice(batch.size())
	_post({"session": _session_payload(), "entries": _render(batch)}, _on_flushed.bind(batch))


# Fold collapsed repeats back into the message. Done here rather than in the
# buffer so a repeat that keeps growing between flushes is only counted once.
func _render(batch: Array) -> Array:
	var out: Array = []
	for record in batch:
		var repeat := int(record.get("repeat", 1))
		if repeat <= 1:
			out.append(record)
			continue
		var copy: Dictionary = record.duplicate()
		copy.erase("repeat")
		copy["message"] = "%s  (x%d)" % [record.message, repeat]
		out.append(copy)
	return out


func _on_flushed(result: int, code: int, body: PackedByteArray, batch: Array) -> void:
	_in_flight = false
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if ok:
		# The spool only ever holds what has not been confirmed, so a crash
		# mid-session re-sends exactly the unacknowledged tail.
		_session_registered = true
		_spool_rewrite()
		var parsed: Variant = _unwrap(JSON.parse_string(body.get_string_from_utf8()))
		var payload: Dictionary = parsed if parsed is Dictionary else {}
		flushed.emit(true, int(payload.get("accepted", batch.size())), int(payload.get("dropped", 0)))
		return

	# 4xx means the server will never accept this batch — retrying forever would
	# pin the buffer at max and drop everything that comes after. Give up on it
	# and keep collecting; the sequence gap records what was lost.
	if code >= 400 and code < 500:
		_spool_rewrite()
		flushed.emit(false, 0, batch.size())
		return

	# Transport failure or a 5xx: the server may well want these. Put them back
	# in front, still in order.
	_pending = batch + _pending
	while _pending.size() > max_buffered:
		_pending.pop_front()
	flushed.emit(false, 0, 0)


# ── Policy ──────────────────────────────────────────────────────────────────


func _fetch_policy() -> void:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			request.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var parsed: Variant = _unwrap(JSON.parse_string(body.get_string_from_utf8()))
			if parsed is Dictionary:
				_apply_policy(parsed)
	)
	var error := request.request(_base_url + _POLICY_PATH, _headers(), HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()


# Every API answer carries its payload under `data`; a server from before that
# change sent it bare, so take either.
func _unwrap(parsed: Variant) -> Variant:
	if parsed is Dictionary and parsed.get("data") is Dictionary:
		return parsed["data"]
	return parsed


func _apply_policy(policy: Dictionary) -> void:
	_enabled = bool(policy.get("enabled", false))
	_level = str(policy.get("level", "info"))
	_batch_max = maxi(1, int(policy.get("batch_max", 200)))
	_category_levels = {}
	var categories: Variant = policy.get("categories", {})
	if categories is Dictionary:
		for key in categories:
			_category_levels[str(key)] = str(categories[key])

	if not _enabled:
		# Told to collect nothing: drop what was held during boot rather than
		# carry it for a session that will never upload.
		_pending.clear()
		_spool_rewrite()
		return

	_flush_previous_run()
	flush()


func _should_collect(entry: Dictionary) -> bool:
	if not _started:
		# Pre-setup: hold it. The policy decides once it arrives.
		return true
	var level := _wire_level(entry.get("severity", 2))
	var category := str(entry.get("category", "general"))
	var floor_level: String = _category_levels.get(category, _level)
	return _rank(level) >= _rank(floor_level)


func _rank(level: String) -> int:
	return int(_RANK.get(level, 2))


# Mirrors DebugLog.Severity ordering: TRACE, DEBUG, INFO, WARNING, ERROR.
func _wire_level(severity: Variant) -> String:
	match int(severity):
		0:
			return "trace"
		1:
			return "debug"
		2:
			return "info"
		3:
			return "warn"
		4:
			return "error"
	return "info"


# ── Transport ───────────────────────────────────────────────────────────────


# The main flush reuses one HTTPRequest (only ever one in flight); recovery and
# policy get their own throwaway ones, because sharing meant whichever request
# started second disconnected the first one's handler and its reply was lost.
func _post(payload: Dictionary, on_done: Callable) -> void:
	for connection in _http.request_completed.get_connections():
		_http.request_completed.disconnect(connection["callable"])
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			on_done.call(result, code, body)
	)
	var error := _http.request(
		_base_url + _INGEST_PATH, _headers(), HTTPClient.METHOD_POST, JSON.stringify(payload)
	)
	if error != OK:
		_in_flight = false


func _post_once(payload: Dictionary) -> void:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	request.request_completed.connect(
		func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			request.queue_free()
	)
	var error := request.request(
		_base_url + _INGEST_PATH, _headers(), HTTPClient.METHOD_POST, JSON.stringify(payload)
	)
	if error != OK:
		request.queue_free()


func _headers() -> PackedStringArray:
	var headers := PackedStringArray(
		["Content-Type: application/json", "x-gamend-session: " + session_id]
	)
	if _token_provider.is_valid():
		var token := str(_token_provider.call())
		if not token.is_empty():
			headers.append("Authorization: Bearer " + token)
	return headers


# The server keys everything off `client_session_id`; the rest describes the run
# and is only read when the session row is first created. So it is sent until a
# batch is accepted and then dropped — at a batch every 10s, re-sending the full
# device description each time is most of the request for none of the meaning.
func _session_payload() -> Dictionary:
	if _session_registered:
		return {"client_session_id": session_id}

	return {
		"client_session_id": session_id,
		"device_id": OS.get_unique_id() if OS.get_name() != "Web" else "",
		"platform": _platform(),
		"app_version": ProjectSettings.get_setting("application/config/version", ""),
		"build": "debug" if OS.is_debug_build() else "release",
		"locale": TranslationServer.get_locale(),
		"started_at": _started_at,
		"meta": _device_meta(),
	}


## What the device is, gathered once.
##
## Everything here answers a question that a log line alone cannot: "only on
## Android 13", "only on the compatibility renderer", "only on the 3GB
## devices", "only in Safari". Without them a reproduction attempt starts by
## asking the player what phone they have.
##
## Cached because none of it changes within a run, and several of these calls
## are not free.
func _device_meta() -> Dictionary:
	if not _meta.is_empty():
		return _meta

	_put(_meta, "os", OS.get_name())
	# "13" / "17.2" / "10.0.19045" — the field that turns "some Android users"
	# into a version range.
	_put(_meta, "os_version", OS.get_version())
	_put(_meta, "distribution", OS.get_distribution_name())
	_put(_meta, "arch", Engine.get_architecture_name())
	_put(_meta, "model", OS.get_model_name())
	_put(_meta, "cpu", OS.get_processor_name())
	_meta["cpu_count"] = OS.get_processor_count()
	_put(_meta, "godot", Engine.get_version_info().get("string", ""))

	# Physical RAM. The number that decides whether a crash was the game or the
	# OS reclaiming it.
	var memory: Dictionary = OS.get_memory_info()
	var physical: int = int(memory.get("physical", 0))
	if physical > 0:
		_meta["ram_mb"] = int(physical / 1048576.0)

	# GPU and the renderer actually in use — not the one configured, which can
	# differ after a driver fallback. Blank under headless, hence the guards.
	_put(_meta, "gpu", RenderingServer.get_video_adapter_name())
	_put(_meta, "gpu_vendor", RenderingServer.get_video_adapter_vendor())
	_put(_meta, "gpu_api", RenderingServer.get_video_adapter_api_version())
	_put(_meta, "rendering", RenderingServer.get_current_rendering_method())

	_collect_display(_meta)
	_collect_web(_meta)
	return _meta


# Screen and window geometry, for the class of bug that only reproduces at one
# size or scale factor. Guarded: a headless or very early call reports zeroes,
# and a zero here reads as a real measurement later.
func _collect_display(meta: Dictionary) -> void:
	var screen: Vector2i = DisplayServer.screen_get_size()
	if screen.x > 0 and screen.y > 0:
		meta["screen"] = "%dx%d" % [screen.x, screen.y]

	var window: Vector2i = DisplayServer.window_get_size()
	if window.x > 0 and window.y > 0:
		meta["window"] = "%dx%d" % [window.x, window.y]

	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi > 0:
		meta["dpi"] = dpi

	var scale: float = DisplayServer.screen_get_scale()
	if scale > 0.0:
		meta["scale"] = scale

	var refresh: float = DisplayServer.screen_get_refresh_rate()
	if refresh > 0.0:
		meta["refresh_hz"] = int(round(refresh))


# On web the ordinary device calls say almost nothing — there is no model and no
# unique id — so the user agent is the only thing that distinguishes a browser
# and version, which is exactly what web-only bugs turn out to depend on.
func _collect_web(meta: Dictionary) -> void:
	if not OS.has_feature("web"):
		return

	_put(meta, "browser", str(JavaScriptBridge.eval("navigator.userAgent", true)))
	_put(meta, "browser_lang", str(JavaScriptBridge.eval("navigator.language", true)))

	var cores: Variant = JavaScriptBridge.eval("navigator.hardwareConcurrency || 0", true)
	if cores is float or cores is int:
		if int(cores) > 0:
			meta["browser_cores"] = int(cores)

	# Chromium-only, and coarse (0.25 / 0.5 / 1 / 2 / 4 / 8), but on web it is
	# the only memory figure available at all.
	var device_memory: Variant = JavaScriptBridge.eval("navigator.deviceMemory || 0", true)
	if device_memory is float or device_memory is int:
		if float(device_memory) > 0.0:
			meta["ram_mb"] = int(float(device_memory) * 1024.0)

	# The shell samples the WASM heap and keeps the high-water mark; the peak is
	# what gets a tab killed on iOS, and it is not visible from anywhere else.
	var peak: Variant = JavaScriptBridge.eval("(window.__heapPeak && window.__heapPeak.mb) || 0", true)
	if peak is float or peak is int:
		if float(peak) > 0.0:
			meta["heap_peak_mb"] = int(peak)


# Blank values are worse than absent ones: they read as a measurement that came
# back empty rather than one that was never taken.
func _put(meta: Dictionary, key: String, value: String) -> void:
	var trimmed := value.strip_edges()
	if not trimmed.is_empty():
		meta[key] = trimmed


func _platform() -> String:
	match OS.get_name():
		"Android":
			return "android"
		"iOS":
			return "ios"
		"Web":
			return "web"
		"Windows", "UWP":
			return "windows"
		"macOS":
			return "macos"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "linux"
	return "unknown"


func _new_session_id() -> String:
	# Crypto, not randi(): a collision would merge two players' runs into one
	# timeline, and the server rejects the second one as a stolen session.
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


# ── Crash survival ──────────────────────────────────────────────────────────


func _spool_write(record: Dictionary) -> void:
	if _spool == null:
		_spool = FileAccess.open(_SPOOL_PATH, FileAccess.WRITE)
		if _spool == null:
			return
	_spool.store_line(JSON.stringify(record))
	# Flushed per line on purpose. A buffered write is the one thing guaranteed
	# not to survive the crash it was meant to explain.
	_spool.flush()


# Rewrite the spool to exactly what is still unacknowledged.
func _spool_rewrite() -> void:
	if _spool != null:
		_spool.close()
		_spool = null
	if _pending.is_empty():
		DirAccess.remove_absolute(_SPOOL_PATH)
		return
	_spool = FileAccess.open(_SPOOL_PATH, FileAccess.WRITE)
	if _spool == null:
		return
	for record in _pending:
		_spool.store_line(JSON.stringify(record))
	_spool.flush()


# The previous run's unacknowledged tail, plus the engine's own log if it left
# one. Uploaded under a fresh session id but tagged so the two can be told
# apart — the point is the lines, not which run object owns them.
func _flush_previous_run() -> void:
	var entries: Array = []
	for record in _recovered:
		record["category"] = "recovered"
		entries.append(record)
	entries.append_array(_engine_tail)
	_recovered = []
	_engine_tail = []
	if entries.is_empty():
		return

	_post_once({"session": _session_payload(), "entries": _render(entries.slice(0, _batch_max))})


func _read_spool() -> Array:
	if not FileAccess.file_exists(_SPOOL_PATH):
		return []
	var file := FileAccess.open(_SPOOL_PATH, FileAccess.READ)
	if file == null:
		return []
	var records: Array = []
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			records.append(parsed)
	file.close()
	DirAccess.remove_absolute(_SPOOL_PATH)
	return records


# The tail of Godot's own log from the previous run. This is where a hard crash
# leaves its stack trace, which the in-memory buffer by definition never has.
func _read_engine_log_tail() -> Array:
	if not FileAccess.file_exists(_ENGINE_LOG_PATH):
		return []
	var file := FileAccess.open(_ENGINE_LOG_PATH, FileAccess.READ)
	if file == null:
		return []
	var lines: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.is_empty():
			lines.append(line)
			if lines.size() > _ENGINE_LOG_TAIL_LINES:
				lines.pop_front()
	file.close()

	# Only worth uploading if it recorded a failure; a clean run's log is noise
	# already covered by the entries we shipped live.
	var interesting := false
	for line in lines:
		var lowered := line.to_lower()
		if lowered.contains("error") or lowered.contains("crash") or lowered.contains("stack trace"):
			interesting = true
			break
	if not interesting:
		return []

	var now := Time.get_unix_time_from_system()
	var entries: Array = []
	for line in lines:
		entries.append(
			{
				"seq": 0,
				"at": now,
				"level": "error",
				"category": "engine_log",
				"message": line,
				"lobby_id": "",
				"screen": "",
			}
		)
	return entries


func _exit_tree() -> void:
	if _spool != null:
		_spool.close()
		_spool = null
