@tool
extends EditorPlugin

# ---------------------------------------------------------------------------
# Glitch Aegis — Editor Plugin (glitch_plugin.gd)
# Registers project settings and the editor dock panel.
# ---------------------------------------------------------------------------

const AUTOLOAD_NAME := "Glitch"
const SINGLETON_PATH := "res://addons/glitch_aegis/glitch_singleton.gd"
const DOCK_SCENE_PATH := "res://addons/glitch_aegis/glitch_dock.tscn"

# All project settings keys
const SETTINGS := {
	# Required credentials
	"title_id":            ["glitch/config/title_id",            "", TYPE_STRING],
	"title_token":         ["glitch/config/title_token",         "", TYPE_STRING],

	# Heartbeat (payout timer)
	"auto_start_heartbeat":["glitch/config/auto_start_heartbeat",true,  TYPE_BOOL],
	"heartbeat_interval":  ["glitch/config/heartbeat_interval",  60,    TYPE_INT],

	# Validation / DRM
	"require_validation":  ["glitch/config/require_validation",  false, TYPE_BOOL],

	# Development helpers
	"test_install_id":     ["glitch/config/test_install_id",     "", TYPE_STRING],
	"game_version":        ["glitch/config/game_version",        "1.0.0", TYPE_STRING],

	# Feature toggles
	"enable_fingerprinting":["glitch/config/enable_fingerprinting", true, TYPE_BOOL],
	"enable_events":       ["glitch/config/enable_events",       true,  TYPE_BOOL],
	"enable_cloud_saves":  ["glitch/config/enable_cloud_saves",  true,  TYPE_BOOL],
}

var _dock: Control = null


func _enter_tree() -> void:
	# Register all custom project settings
	for key in SETTINGS:
		var entry: Array = SETTINGS[key]
		_add_project_setting(entry[0], entry[1], entry[2])

	# Register the background Autoload singleton
	add_autoload_singleton(AUTOLOAD_NAME, SINGLETON_PATH)

	# Add the editor console dock to the bottom panel
	if ResourceLoader.exists(DOCK_SCENE_PATH):
		_dock = preload("res://addons/glitch_aegis/glitch_dock.tscn").instantiate()
		add_control_to_bottom_panel(_dock, "Glitch Console")


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
	# Note: We intentionally leave project settings intact so developer
	# configuration is not lost if the plugin is temporarily disabled.


func _add_project_setting(setting_name: String, default_value, type: int) -> void:
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, default_value)

	var info := {
		"name": setting_name,
		"type": type,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
	}
	ProjectSettings.add_property_info(info)
	ProjectSettings.set_initial_value(setting_name, default_value)
