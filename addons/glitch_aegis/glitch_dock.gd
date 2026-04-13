@tool
# ===========================================================================
# Glitch Aegis — Editor Dock (glitch_dock.gd)
# Appears as "Glitch Console" in the bottom panel of the Godot editor.
# ===========================================================================
extends Control

# Node references (filled by the scene tree)
@onready var _status_label:   Label  = $Root/StatusContainer/StatusLabel
@onready var _connect_btn:    Button = $Root/ButtonRow/ConnectBtn
@onready var _docs_btn:       Button = $Root/ButtonRow/DocsBtn
@onready var _title_id_label: Label  = $Root/InfoGrid/TitleIDValue
@onready var _token_label:    Label  = $Root/InfoGrid/TokenValue
@onready var _test_id_label:  Label  = $Root/InfoGrid/TestIDValue
@onready var _heartbeat_label:Label  = $Root/InfoGrid/HeartbeatValue
@onready var _validate_label: Label  = $Root/InfoGrid/ValidateValue
@onready var _ach_label:      Label  = $Root/InfoGrid/AchievementsValue
@onready var _steam_label:    Label  = $Root/InfoGrid/SteamBridgeValue

var _http_node: HTTPRequest = null


func _ready() -> void:
	_refresh_display()


## Refresh the labels to show current Project Settings values.
func _refresh_display() -> void:
	var tid   := ProjectSettings.get_setting("glitch/config/title_id",           "")
	var token := ProjectSettings.get_setting("glitch/config/title_token",         "")
	var test  := ProjectSettings.get_setting("glitch/config/test_install_id",     "")
	var hb    := ProjectSettings.get_setting("glitch/config/auto_start_heartbeat",true)
	var rv    := ProjectSettings.get_setting("glitch/config/require_validation",  false)

	if is_instance_valid(_title_id_label):
		_title_id_label.text = tid if not tid.is_empty() else "(not set)"
	if is_instance_valid(_token_label):
		_token_label.text = ("*" * min(token.length(), 8)) + "…" if token.length() > 4 else "(not set)"
	if is_instance_valid(_test_id_label):
		_test_id_label.text = test if not test.is_empty() else "(not set)"
	if is_instance_valid(_heartbeat_label):
		_heartbeat_label.text = "Enabled" if hb else "Disabled"
	if is_instance_valid(_validate_label):
		_validate_label.text = "Required" if rv else "Optional"

	var ach   := ProjectSettings.get_setting("glitch/config/enable_achievements",true)
	var steam := ProjectSettings.get_setting("glitch/config/enable_steam_bridge", false)
	if is_instance_valid(_ach_label):
		_ach_label.text = "Enabled" if ach else "Disabled"
	if is_instance_valid(_steam_label):
		_steam_label.text = "Enabled" if steam else "Disabled"


## Called when the "Test API Connection" button is pressed.
func _on_connect_btn_pressed() -> void:
	var tid   := ProjectSettings.get_setting("glitch/config/title_id",   "")
	var token := ProjectSettings.get_setting("glitch/config/title_token", "")

	if tid.is_empty() or token.is_empty():
		_set_status("❌  Missing Title ID or Token in Project Settings > Glitch > Config", Color.ORANGE_RED)
		return

	_set_status("⏳  Connecting to Glitch…", Color.YELLOW)
	_connect_btn.disabled = true

	if is_instance_valid(_http_node):
		_http_node.queue_free()
	_http_node = HTTPRequest.new()
	add_child(_http_node)
	_http_node.request_completed.connect(_on_test_response)

	var url := "https://api.glitch.fun/api/titles/%s" % tid
	var headers := PackedStringArray(["Authorization: Bearer " + token, "Accept: application/json"])
	_http_node.request(url, headers, HTTPClient.METHOD_GET)


func _on_test_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_connect_btn.disabled = false
	if is_instance_valid(_http_node):
		_http_node.queue_free()
		_http_node = null

	if code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		var name := ""
		if parsed is Dictionary:
			name = parsed.get("data", {}).get("name", "")
		var msg := "✅  Connected!  Game: \"%s\"" % name if name else "✅  Connected to Glitch!"
		_set_status(msg, Color.GREEN)
	elif code == 401 or code == 403:
		_set_status("❌  Auth failed (HTTP %d) — check your Title Token." % code, Color.ORANGE_RED)
	elif code == 404:
		_set_status("❌  Title not found (HTTP 404) — check your Title ID.", Color.ORANGE_RED)
	else:
		_set_status("⚠️  Unexpected response: HTTP %d" % code, Color.ORANGE)


## Open the Glitch developer docs in the default browser.
func _on_docs_btn_pressed() -> void:
	OS.shell_open("https://docs.glitch.fun")


## Refresh displayed values (user presses "Refresh").
func _on_refresh_btn_pressed() -> void:
	_refresh_display()
	_set_status("ℹ️  Settings refreshed.", Color.CORNFLOWER_BLUE)


func _set_status(msg: String, color: Color = Color.WHITE) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = msg
		_status_label.add_theme_color_override("font_color", color)
