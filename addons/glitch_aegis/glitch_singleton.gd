# ===========================================================================
# Glitch Aegis v3.0 — Singleton (glitch_singleton.gd)
# Autoloaded as "Glitch". Provides payouts, DRM, achievements, leaderboards,
# cloud saves, analytics, purchases, fingerprinting, and Steam-to-Glitch bridge.
#
# Compatible with Godot 4.x
# ===========================================================================
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal handshake_succeeded(install_uuid: String)
signal handshake_failed(reason: String)
signal validation_succeeded(user_name: String, license_type: String)
signal validation_failed(reason: String)
signal heartbeat_sent
signal save_uploaded(version: int)
signal save_conflict_detected(conflict_id: String, server_version: int)
signal save_list_received(saves: Array)
signal achievements_loaded(success: bool)
signal achievement_unlocked(api_key: String)
signal leaderboard_received(board_key: String, entries: Array)

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var title_id: String = ""
var title_token: String = ""
var install_id: String = ""          # The install UUID returned by the server
var user_install_id: String = ""     # The raw ID we send (from URL / test / CLI)
var game_version: String = "1.0.0"

var _heartbeat_timer: Timer = null
var _heartbeat_active: bool = false
var _heartbeat_interval: float = 60.0
var _require_validation: bool = false
var _enable_fingerprinting: bool = true
var _enable_events: bool = true
var _enable_cloud_saves: bool = true
var _enable_achievements: bool = true
var _enable_leaderboards: bool = true
var _enable_steam_bridge: bool = false
var _access_denied_overlay: CanvasLayer = null
var _is_initialized: bool = false

# Tracks the last known save version per slot for conflict detection
var _save_versions: Dictionary = {}   # { slot_index -> version }

# Achievement cache: { "api_key" -> { "status": "locked"|"unlocked", "progress": float } }
var _achievement_cache: Dictionary = {}
var _achievements_loaded: bool = false

# Steam bridge pending buffers
var _steam_pending_stats: Dictionary = {}    # { api_key -> value }
var _steam_pending_scores: Dictionary = {}   # { board_key -> score }


# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	_load_settings()

	if title_id.is_empty() or title_token.is_empty():
		push_warning("Glitch Aegis: Title ID or Token is not set in Project Settings > Glitch > Config.")
		return

	var auto_start: bool = ProjectSettings.get_setting("glitch/config/auto_start_heartbeat", true)
	if auto_start:
		initialize()


# ---------------------------------------------------------------------------
# PUBLIC API — Core
# ---------------------------------------------------------------------------

## Call this manually if auto_start_heartbeat is disabled.
func initialize() -> void:
	if _is_initialized:
		return
	_is_initialized = true

	user_install_id = _resolve_install_id()

	if user_install_id.is_empty():
		if _require_validation:
			_show_access_denied("No valid game session found.\nPlease launch this game from the Glitch platform.")
		else:
			push_warning("Glitch Aegis: No install_id found. Payouts disabled. Set a Test Install ID in Project Settings for local testing.")
		return

	await _register_install()


## Start the payout heartbeat manually.
func start_heartbeat() -> void:
	if _heartbeat_active:
		return
	if user_install_id.is_empty():
		push_warning("Glitch Aegis: Cannot start heartbeat — no install ID.")
		return
	_heartbeat_active = true
	_create_heartbeat_timer()
	_send_heartbeat()


## Stop the payout heartbeat.
func stop_heartbeat() -> void:
	_heartbeat_active = false
	if _heartbeat_timer and is_instance_valid(_heartbeat_timer):
		_heartbeat_timer.stop()
		_heartbeat_timer.queue_free()
		_heartbeat_timer = null


## Returns true if the heartbeat is currently running.
func is_heartbeat_active() -> bool:
	return _heartbeat_active


## Manually validate the current session.
func validate_session() -> Dictionary:
	if install_id.is_empty():
		return {"valid": false, "reason": "NO_INSTALL_ID"}
	return await _do_validation(install_id)


# ---------------------------------------------------------------------------
# PUBLIC API — Achievements
# ---------------------------------------------------------------------------

## Report progress toward an achievement. If progress meets the threshold,
## Glitch unlocks it automatically. Use value=1 for simple one-shot unlocks.
##
## Example: Glitch.report_achievement("boss_killed", 1)
## Example: Glitch.report_achievement("coin_collector", 50)
func report_achievement(api_key: String, value: float = 1.0) -> void:
	if not _enable_achievements:
		return
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot report achievement — not yet initialized.")
		return

	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/submit" % [title_id, install_id]
	var payload := {
		"idempotency_key": _uuid4(),
		"payload": {
			"stats": { api_key: value }
		}
	}

	var http := _new_http()
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))
	var response: Array = await http.request_completed
	http.queue_free()

	var code: int = response[1]
	if code >= 200 and code < 300:
		print("Glitch Aegis: Achievement progress sent: %s = %s" % [api_key, str(value)])
		# Check for newly unlocked
		var body: Dictionary = _parse_json(response[3].get_string_from_utf8())
		var newly := body.get("newly_unlocked", [])
		if newly is Array:
			for ach in newly:
				if ach is Dictionary:
					var key: String = ach.get("api_key", "")
					if not key.is_empty():
						_achievement_cache[key] = {"status": "unlocked", "progress": value}
						emit_signal("achievement_unlocked", key)
						print("Glitch Aegis: Achievement UNLOCKED: %s" % key)
	else:
		push_warning("Glitch Aegis: Achievement report failed (HTTP %d)" % code)


## Check if an achievement is unlocked (uses local cache — instant, no network).
##
## Example: if Glitch.is_achievement_unlocked("boss_killed"): show_trophy()
func is_achievement_unlocked(api_key: String) -> bool:
	var ach: Dictionary = _achievement_cache.get(api_key, {})
	return ach.get("status", "locked") == "unlocked"


## Get the progress value of an achievement (local cache).
func get_achievement_progress(api_key: String) -> float:
	var ach: Dictionary = _achievement_cache.get(api_key, {})
	return float(ach.get("progress", 0))


## Force-reload achievement data from the server.
func refresh_achievements() -> void:
	await _load_achievements()


# ---------------------------------------------------------------------------
# PUBLIC API — Leaderboards
# ---------------------------------------------------------------------------

## Submit a score to a leaderboard.
##
## Example: Glitch.submit_score("high_score", 5000)
func submit_score(board_key: String, score: float) -> void:
	if not _enable_leaderboards:
		return
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot submit score — not yet initialized.")
		return

	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/submit" % [title_id, install_id]
	var payload := {
		"idempotency_key": _uuid4(),
		"payload": {
			"scores": { board_key: score }
		}
	}

	var http := _new_http()
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))
	var response: Array = await http.request_completed
	http.queue_free()

	if response[1] >= 200 and response[1] < 300:
		print("Glitch Aegis: Score submitted: %s = %s" % [board_key, str(score)])
	else:
		push_warning("Glitch Aegis: Score submission failed (HTTP %d)" % response[1])


## Download leaderboard entries. Returns an Array of Dictionaries.
## Also emits leaderboard_received(board_key, entries).
##
## Example: var entries = await Glitch.get_leaderboard("high_score")
func get_leaderboard(board_key: String) -> Array:
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot get leaderboard — not yet initialized.")
		return []

	var url := "https://api.glitch.fun/api/titles/%s/leaderboards/%s" % [title_id, board_key]
	var http := _new_http()
	http.request(url, _auth_headers(), HTTPClient.METHOD_GET)

	var response: Array = await http.request_completed
	http.queue_free()

	if response[1] == 200:
		var result: Dictionary = _parse_json(response[3].get_string_from_utf8())
		var entries: Array = result.get("data", [])
		emit_signal("leaderboard_received", board_key, entries)
		return entries
	push_warning("Glitch Aegis: Leaderboard download failed (HTTP %d)" % response[1])
	return []


# ---------------------------------------------------------------------------
# PUBLIC API — Steam-to-Glitch Bridge
# ---------------------------------------------------------------------------

## Drop-in replacement for Steamworks set_achievement().
## Buffers the unlock until steam_store_stats() is called.
##
## Example: Glitch.steam_set_achievement("ACH_WIN_GAME")
func steam_set_achievement(api_name: String) -> void:
	_steam_pending_stats[api_name] = 100.0
	print("Glitch Steam Bridge: SetAchievement('%s') buffered." % api_name)


## Drop-in replacement for Steamworks set_stat().
func steam_set_stat_int(stat_name: String, value: int) -> void:
	_steam_pending_stats[stat_name] = float(value)


## Drop-in replacement for Steamworks set_stat() (float variant).
func steam_set_stat_float(stat_name: String, value: float) -> void:
	_steam_pending_stats[stat_name] = value


## Drop-in replacement for Steamworks upload_leaderboard_score().
## Buffers the score until steam_store_stats() is called.
func steam_upload_score(board_key: String, score: float) -> void:
	_steam_pending_scores[board_key] = score
	print("Glitch Steam Bridge: UploadScore('%s', %s) buffered." % [board_key, str(score)])


## Drop-in replacement for Steamworks get_achievement().
## Returns true if the achievement is unlocked (local cache).
func steam_get_achievement(api_name: String) -> bool:
	return is_achievement_unlocked(api_name)


## Drop-in replacement for Steamworks store_stats().
## Flushes all buffered achievements and scores to Glitch in one request.
##
## Example:
##   Glitch.steam_set_achievement("ACH_WIN_GAME")
##   Glitch.steam_upload_score("high_score", 5000)
##   Glitch.steam_store_stats()
func steam_store_stats() -> void:
	if install_id.is_empty():
		push_warning("Glitch Steam Bridge: Cannot flush — not initialized.")
		return

	if _steam_pending_stats.is_empty() and _steam_pending_scores.is_empty():
		return

	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/submit" % [title_id, install_id]
	var inner: Dictionary = {}
	if not _steam_pending_stats.is_empty():
		inner["stats"] = _steam_pending_stats.duplicate()
	if not _steam_pending_scores.is_empty():
		inner["scores"] = _steam_pending_scores.duplicate()

	var payload := {
		"idempotency_key": _uuid4(),
		"payload": inner,
	}

	_post_json(url, payload)
	print("Glitch Steam Bridge: Flushed %d stats + %d scores to Glitch." % [_steam_pending_stats.size(), _steam_pending_scores.size()])

	_steam_pending_stats.clear()
	_steam_pending_scores.clear()


## Drop-in replacement for Steamworks request_current_stats().
## Refreshes the achievement cache from the Glitch server.
func steam_request_stats() -> void:
	await _load_achievements()


# ---------------------------------------------------------------------------
# PUBLIC API — Analytics Events
# ---------------------------------------------------------------------------

## Track a single gameplay event (for funnel analysis in your dashboard).
func track_event(step_key: String, action_key: String, metadata: Dictionary = {}) -> void:
	if not _enable_events:
		return
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot track event — not yet initialized.")
		return

	var url := "https://api.glitch.fun/api/titles/%s/events" % title_id
	var data := {
		"game_install_id": install_id,
		"step_key": step_key,
		"action_key": action_key,
		"metadata": metadata,
		"event_timestamp": _iso_timestamp(),
	}
	_post_json(url, data)


## Send multiple events in one network request.
func track_events_bulk(events: Array) -> void:
	if not _enable_events:
		return
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot bulk-track events — not yet initialized.")
		return

	var enriched: Array = []
	for ev in events:
		var e: Dictionary = ev.duplicate()
		if not e.has("game_install_id"):
			e["game_install_id"] = install_id
		if not e.has("event_timestamp"):
			e["event_timestamp"] = _iso_timestamp()
		enriched.append(e)

	var url := "https://api.glitch.fun/api/titles/%s/events/bulk" % title_id
	_post_json(url, {"events": enriched})


# ---------------------------------------------------------------------------
# PUBLIC API — Cloud Saves
# ---------------------------------------------------------------------------

## Upload a save to the cloud.
func upload_save(slot_index: int, save_data: Dictionary, save_type: String = "manual", base_version: int = -1) -> void:
	if not _enable_cloud_saves:
		return
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot save — not yet initialized.")
		return

	var version := base_version
	if version < 0:
		version = _save_versions.get(slot_index, 0)

	var json_str: String = JSON.stringify(save_data)
	var bytes: PackedByteArray = json_str.to_utf8_buffer()

	var payload := {
		"slot_index": slot_index,
		"payload": Marshalls.raw_to_base64(bytes),
		"checksum": _sha256_hex(bytes),
		"save_type": save_type,
		"client_timestamp": _iso_timestamp(),
		"base_version": version,
	}

	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/saves" % [title_id, install_id]
	var http := _new_http()
	var headers := _auth_json_headers()
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

	var response: Array = await http.request_completed
	http.queue_free()

	var code: int = response[1]
	var body: String = response[3].get_string_from_utf8()

	if code == 201 or code == 200:
		var result: Dictionary = _parse_json(body)
		var new_version: int = result.get("data", {}).get("version", version + 1)
		_save_versions[slot_index] = new_version
		emit_signal("save_uploaded", new_version)
	elif code == 409:
		var result: Dictionary = _parse_json(body)
		var conflict_id: String = result.get("conflict_id", "")
		var server_ver: int = result.get("server_version", 0)
		_save_versions[slot_index] = server_ver
		emit_signal("save_conflict_detected", conflict_id, server_ver)
	else:
		push_warning("Glitch Aegis: upload_save failed with HTTP %d" % code)


## Fetch all cloud save slots for this player.
func list_saves() -> Array:
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot list saves — not yet initialized.")
		return []

	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/saves" % [title_id, install_id]
	var http := _new_http()
	http.request(url, _auth_headers(), HTTPClient.METHOD_GET)

	var response: Array = await http.request_completed
	http.queue_free()

	if response[1] == 200:
		var result: Dictionary = _parse_json(response[3].get_string_from_utf8())
		var saves: Array = result.get("data", [])
		for s in saves:
			_save_versions[s.get("slot_index", 0)] = s.get("version", 0)
		emit_signal("save_list_received", saves)
		return saves
	return []


## Resolve a save conflict after receiving save_conflict_detected.
func resolve_save_conflict(save_id: String, conflict_id: String, choice: String) -> bool:
	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/saves/%s/resolve" % [title_id, install_id, save_id]
	var http := _new_http()
	var body := JSON.stringify({"conflict_id": conflict_id, "choice": choice})
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, body)

	var response: Array = await http.request_completed
	http.queue_free()
	return response[1] == 200


# ---------------------------------------------------------------------------
# PUBLIC API — Purchases
# ---------------------------------------------------------------------------

## Record an in-game purchase or revenue event.
func track_purchase(data: Dictionary) -> void:
	if install_id.is_empty():
		push_warning("Glitch Aegis: Cannot track purchase — not yet initialized.")
		return
	var payload := data.duplicate()
	payload["game_install_id"] = install_id
	var url := "https://api.glitch.fun/api/titles/%s/purchases" % title_id
	_post_json(url, payload)


# ---------------------------------------------------------------------------
# PUBLIC API — Access Denied
# ---------------------------------------------------------------------------

## Show the access-denied overlay manually.
func show_access_denied(message: String = "") -> void:
	_show_access_denied(message)


## Hide the access-denied overlay.
func hide_access_denied() -> void:
	if _access_denied_overlay and is_instance_valid(_access_denied_overlay):
		_access_denied_overlay.queue_free()
		_access_denied_overlay = null


# ---------------------------------------------------------------------------
# INTERNAL — initialization flow
# ---------------------------------------------------------------------------

func _load_settings() -> void:
	title_id            = ProjectSettings.get_setting("glitch/config/title_id",             "")
	title_token         = ProjectSettings.get_setting("glitch/config/title_token",           "")
	_heartbeat_interval = float(ProjectSettings.get_setting("glitch/config/heartbeat_interval", 60))
	_require_validation = ProjectSettings.get_setting("glitch/config/require_validation",    false)
	_enable_fingerprinting = ProjectSettings.get_setting("glitch/config/enable_fingerprinting", true)
	_enable_events      = ProjectSettings.get_setting("glitch/config/enable_events",         true)
	_enable_cloud_saves = ProjectSettings.get_setting("glitch/config/enable_cloud_saves",    true)
	_enable_achievements = ProjectSettings.get_setting("glitch/config/enable_achievements",  true)
	_enable_leaderboards = ProjectSettings.get_setting("glitch/config/enable_leaderboards",  true)
	_enable_steam_bridge = ProjectSettings.get_setting("glitch/config/enable_steam_bridge",  false)
	game_version        = ProjectSettings.get_setting("glitch/config/game_version",          "1.0.0")


func _resolve_install_id() -> String:
	# --- Web export: read from URL ---
	if OS.has_feature("web"):
		var from_url: String = JavaScriptBridge.eval(
			"(new URLSearchParams(window.location.search)).get('install_id') || ''"
		)
		if not from_url.is_empty() and from_url != "null":
			print("Glitch Aegis: install_id from URL: ", from_url)
			return from_url

	# --- Desktop: read from command-line ---
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--install_id="):
			var cli_id: String = arg.split("=", true, 1)[1]
			if not cli_id.is_empty():
				print("Glitch Aegis: install_id from CLI: ", cli_id)
				return cli_id
		elif arg.begins_with("--glitch_install_id="):
			var cli_id: String = arg.split("=", true, 1)[1]
			if not cli_id.is_empty():
				return cli_id

	# --- Environment variable fallback ---
	if OS.has_environment("GLITCH_INSTALL_ID"):
		var env_id: String = OS.get_environment("GLITCH_INSTALL_ID")
		if not env_id.is_empty():
			print("Glitch Aegis: install_id from env var: ", env_id)
			return env_id

	# --- Test ID from Project Settings ---
	var test_id: String = ProjectSettings.get_setting("glitch/config/test_install_id", "")
	if not test_id.is_empty():
		print("Glitch Aegis: Using test_install_id from Project Settings: ", test_id)
		return test_id

	return ""


func _register_install() -> void:
	var platform := _detect_platform()
	var data: Dictionary = {
		"user_install_id": user_install_id,
		"platform": platform,
		"game_version": game_version,
		"device_type": _device_type_string(),
		"operating_system": OS.get_name() + " " + OS.get_version(),
	}

	if _enable_fingerprinting:
		data["fingerprint_components"] = _build_fingerprint()

	var url := "https://api.glitch.fun/api/titles/%s/installs" % title_id
	var http := _new_http()
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, JSON.stringify(data))

	var response: Array = await http.request_completed
	http.queue_free()

	var code: int = response[1]
	if code == 200 or code == 201:
		var result: Dictionary = _parse_json(response[3].get_string_from_utf8())
		install_id = result.get("data", {}).get("id", user_install_id)
		print("Glitch Aegis: Session registered. install UUID = ", install_id)
		emit_signal("handshake_succeeded", install_id)

		if _require_validation:
			var ok: bool = await _run_validation_check()
			if ok:
				_maybe_start_heartbeat()
		else:
			_maybe_start_heartbeat()

		# Auto-load achievements after session is registered
		if _enable_achievements:
			_load_achievements()
	else:
		push_warning("Glitch Aegis: Install registration failed (HTTP %d)" % code)
		emit_signal("handshake_failed", "HTTP %d" % code)
		if _require_validation:
			_show_access_denied("Could not connect to the Glitch platform.\nPlease check your internet connection and try again.")


func _maybe_start_heartbeat() -> void:
	var auto_start: bool = ProjectSettings.get_setting("glitch/config/auto_start_heartbeat", true)
	if auto_start:
		start_heartbeat()


func _run_validation_check() -> bool:
	var result: Dictionary = await _do_validation(install_id)
	if result.get("valid", false):
		var uname: String = result.get("user_name", "")
		var ltype: String = result.get("license_type", "")
		print("Glitch Aegis: License valid — user: %s (%s)" % [uname, ltype])
		emit_signal("validation_succeeded", uname, ltype)
		return true
	else:
		var reason: String = result.get("reason", "UNKNOWN")
		print("Glitch Aegis: Validation failed — ", reason)
		emit_signal("validation_failed", reason)
		if _require_validation:
			_show_access_denied(_access_denied_message_for(reason))
		return false


func _do_validation(iid: String) -> Dictionary:
	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/validate" % [title_id, iid]
	var http := _new_http()
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, "{}")

	var response: Array = await http.request_completed
	http.queue_free()

	var code: int = response[1]
	if code == 200:
		var body: Dictionary = _parse_json(response[3].get_string_from_utf8())
		var inner: Dictionary = body.get("data", body)
		inner["valid"] = true
		return inner
	else:
		var body: Dictionary = _parse_json(response[3].get_string_from_utf8())
		body["valid"] = false
		if not body.has("reason"):
			body["reason"] = "HTTP_%d" % code
		return body


func _access_denied_message_for(reason: String) -> String:
	match reason:
		"LICENSE_EXPIRED":
			return "Your access to this game has expired.\nVisit the Glitch store to renew your license."
		"TRIAL_ENDED":
			return "Your free trial has ended.\nPurchase the full game on the Glitch platform to continue."
		"NO_LICENSE":
			return "You don't have a license for this game.\nVisit the Glitch store to get access."
		_:
			return "Access denied.\nPlease return to the Glitch platform to verify your license.\n\nCode: " + reason


# ---------------------------------------------------------------------------
# INTERNAL — Achievement Loading
# ---------------------------------------------------------------------------

func _load_achievements() -> void:
	if install_id.is_empty():
		return

	var url := "https://api.glitch.fun/api/titles/%s/installs/%s/achievements" % [title_id, install_id]
	var http := _new_http()
	http.request(url, _auth_headers(), HTTPClient.METHOD_GET)

	var response: Array = await http.request_completed
	http.queue_free()

	if response[1] >= 200 and response[1] < 300:
		var result: Dictionary = _parse_json(response[3].get_string_from_utf8())
		var items: Array = result.get("data", [])
		_achievement_cache.clear()
		for item in items:
			if item is Dictionary:
				var api_key: String = item.get("api_key", "")
				if not api_key.is_empty():
					_achievement_cache[api_key] = {
						"status": item.get("status", "locked"),
						"progress": float(item.get("progress_value", 0)),
					}
		_achievements_loaded = true
		print("Glitch Aegis: Achievements loaded (%d entries)." % _achievement_cache.size())
		emit_signal("achievements_loaded", true)
	else:
		push_warning("Glitch Aegis: Achievement load failed (HTTP %d). Player may be a guest." % response[1])
		emit_signal("achievements_loaded", false)


# ---------------------------------------------------------------------------
# HEARTBEAT
# ---------------------------------------------------------------------------

func _create_heartbeat_timer() -> void:
	if _heartbeat_timer and is_instance_valid(_heartbeat_timer):
		_heartbeat_timer.queue_free()
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = _heartbeat_interval
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()


func _send_heartbeat() -> void:
	if not _heartbeat_active or user_install_id.is_empty():
		return

	var platform := _detect_platform()
	var data: Dictionary = {
		"user_install_id": user_install_id,
		"platform": platform,
		"game_version": game_version,
		"device_type": _device_type_string(),
		"operating_system": OS.get_name() + " " + OS.get_version(),
	}

	if _enable_fingerprinting:
		data["fingerprint_components"] = _build_fingerprint()

	var url := "https://api.glitch.fun/api/titles/%s/installs" % title_id
	var http := _new_http()
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, JSON.stringify(data))

	var response: Array = await http.request_completed
	http.queue_free()

	var code: int = response[1]
	if code == 200 or code == 201:
		emit_signal("heartbeat_sent")
	elif code == 403:
		stop_heartbeat()
		if _require_validation:
			_show_access_denied("Your session has been terminated by the Glitch platform.\n\nCode: 403 Forbidden")
	else:
		push_warning("Glitch Aegis: Heartbeat returned HTTP %d" % code)


# ---------------------------------------------------------------------------
# ACCESS DENIED OVERLAY
# ---------------------------------------------------------------------------

func _show_access_denied(message: String) -> void:
	if _access_denied_overlay and is_instance_valid(_access_denied_overlay):
		return

	_access_denied_overlay = CanvasLayer.new()
	_access_denied_overlay.layer = 128
	_access_denied_overlay.name = "GlitchAccessDenied"

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_access_denied_overlay.add_child(bg)

	var container := VBoxContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.custom_minimum_size = Vector2(520, 0)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(container)

	var title_lbl := Label.new()
	title_lbl.text = "🔒  Access Denied"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	container.add_child(title_lbl)

	var sep1 := HSeparator.new()
	container.add_child(sep1)

	var msg_lbl := Label.new()
	msg_lbl.text = message if message else "You do not have a valid license for this game."
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.custom_minimum_size = Vector2(480, 0)
	msg_lbl.add_theme_color_override("font_color", Color.WHITE)
	msg_lbl.add_theme_font_size_override("font_size", 16)
	container.add_child(msg_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	container.add_child(spacer)

	var store_btn := Button.new()
	store_btn.text = "Visit Glitch Store"
	store_btn.custom_minimum_size = Vector2(280, 48)
	store_btn.add_theme_font_size_override("font_size", 16)
	store_btn.pressed.connect(_on_store_button_pressed)
	container.add_child(store_btn)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	container.add_child(spacer2)

	var footer := Label.new()
	footer.text = "Powered by Glitch Aegis DRM"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	footer.add_theme_font_size_override("font_size", 11)
	container.add_child(footer)

	get_tree().root.call_deferred("add_child", _access_denied_overlay)
	get_tree().paused = true


func _on_store_button_pressed() -> void:
	var store_url := "https://glitch.fun/games/%s" % title_id
	OS.shell_open(store_url)


# ---------------------------------------------------------------------------
# FINGERPRINTING
# ---------------------------------------------------------------------------

func _build_fingerprint() -> Dictionary:
	var fp: Dictionary = {}

	fp["device"] = {
		"model": _get_device_model(),
		"type": _device_type_string(),
		"manufacturer": _get_manufacturer(),
	}

	fp["os"] = {
		"name": OS.get_name(),
		"version": OS.get_version(),
	}

	var screen_size := DisplayServer.screen_get_size()
	fp["display"] = {
		"resolution": "%dx%d" % [screen_size.x, screen_size.y],
		"density": DisplayServer.screen_get_dpi(),
	}

	fp["hardware"] = {
		"cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(),
	}

	fp["environment"] = {
		"language": OS.get_locale(),
		"timezone": Time.get_time_zone_from_system().get("name", ""),
	}

	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		fp["desktop_data"] = {
			"formFactors": ["Desktop"],
			"architecture": Engine.get_architecture_name() if Engine.has_method("get_architecture_name") else "x86",
			"bitness": "64" if OS.has_feature("64") else "32",
			"platformVersion": OS.get_version(),
			"wow64": false,
		}

	if OS.has_feature("web") and _enable_fingerprinting:
		var layout: Dictionary = _get_web_keyboard_layout()
		if not layout.is_empty():
			fp["keyboard_layout"] = layout

	return fp


func _get_device_model() -> String:
	var os_name := OS.get_name()
	var cpu := OS.get_processor_name()
	if os_name == "Windows" or os_name == "macOS" or os_name == "Linux":
		return "%s (%d-core %s)" % [os_name, OS.get_processor_count(), cpu.left(30)]
	return cpu.left(50) if not cpu.is_empty() else "Unknown"


func _get_manufacturer() -> String:
	match OS.get_name():
		"Windows": return "Microsoft"
		"macOS":   return "Apple"
		"iOS":     return "Apple"
		"Android": return OS.get_model_name().split(" ")[0] if OS.has_method("get_model_name") else "Android OEM"
		_:         return "Unknown"


func _device_type_string() -> String:
	if OS.has_feature("mobile"):
		if DisplayServer.screen_get_size().x < 800:
			return "mobile"
		return "tablet"
	if OS.has_feature("web"):
		return "desktop"
	return "desktop"


func _detect_platform() -> String:
	if OS.has_feature("web"):   return "web"
	if OS.has_feature("windows"): return "windows"
	if OS.has_feature("macos"):   return "macos"
	if OS.has_feature("linux"):   return "linux"
	if OS.has_feature("ios"):     return "ios"
	if OS.has_feature("android"): return "android"
	return OS.get_name().to_lower()


func _get_web_keyboard_layout() -> Dictionary:
	if not OS.has_feature("web"):
		return {}

	var key_codes := [
		"KeyQ","KeyW","KeyE","KeyR","KeyT","KeyY","KeyU","KeyI","KeyO","KeyP",
		"KeyA","KeyS","KeyD","KeyF","KeyG","KeyH","KeyJ","KeyK","KeyL",
		"KeyZ","KeyX","KeyC","KeyV","KeyB","KeyN","KeyM",
		"Backquote","Digit1","Digit2","Digit3","Digit4","Digit5",
		"Digit6","Digit7","Digit8","Digit9","Digit0",
		"Minus","Equal","BracketLeft","BracketRight","Backslash",
		"Semicolon","Quote","Comma","Period","Slash"
	]

	var js_code := """
(function(){
  try {
    var layout = {};
    var keys = %s;
    var kb = navigator.keyboard;
    if (!kb || !kb.getLayoutMap) return '{}';
    var map = {};
    keys.forEach(function(code){
      var ev = new KeyboardEvent('keydown', {code: code});
      map[code] = ev.key || code;
    });
    return JSON.stringify(map);
  } catch(e) { return '{}'; }
})()
""" % JSON.stringify(key_codes)

	var result: String = JavaScriptBridge.eval(js_code, true)
	if result and result != "null":
		return _parse_json(result)
	return {}


# ---------------------------------------------------------------------------
# UTILITY HELPERS
# ---------------------------------------------------------------------------

func _new_http() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.use_threads = false
	http.timeout = 15.0
	add_child(http)
	return http


func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + title_token,
		"Accept: application/json",
	])


func _auth_json_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + title_token,
		"Content-Type: application/json",
		"Accept: application/json",
	])


func _post_json(url: String, data: Dictionary) -> void:
	var http := _new_http()
	http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, JSON.stringify(data))
	var response: Array = await http.request_completed
	http.queue_free()
	if response[1] >= 400:
		push_warning("Glitch Aegis: POST to %s failed (HTTP %d)" % [url, response[1]])


func _parse_json(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _iso_timestamp() -> String:
	return Time.get_datetime_string_from_system(true)


func _uuid4() -> String:
	var hex := "0123456789abcdef"
	var uuid := ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		if i == 12:
			uuid += "4"
		elif i == 16:
			uuid += hex[randi() % 4 + 8]
		else:
			uuid += hex[randi() % 16]
	return uuid
