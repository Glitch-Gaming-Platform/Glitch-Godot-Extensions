@tool
extends EditorPlugin

const AUTOLOAD_NAME = "Glitch"
const SETTING_TITLE_ID = "glitch/config/title_id"
const SETTING_TITLE_TOKEN = "glitch/config/title_token"
const SETTING_AUTO_START = "glitch/config/auto_start_handshake"

func _enter_tree():
	# 1. Add Custom Project Settings
	_add_project_setting(SETTING_TITLE_ID, "", TYPE_STRING)
	_add_project_setting(SETTING_TITLE_TOKEN, "", TYPE_STRING)
	_add_project_setting(SETTING_AUTO_START, true, TYPE_BOOL)
	
	# 2. Register the Autoload (The background manager)
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/glitch_aegis/glitch_singleton.gd")
	
	# 3. Add the Editor Dock
	var dock = preload("res://addons/glitch_aegis/glitch_dock.tscn").instantiate()
	add_control_to_bottom_panel(dock, "Glitch Console")

func _exit_tree():
	remove_autoload_singleton(AUTOLOAD_NAME)
	# Note: We leave project settings so they aren't wiped on accidental disable

func _add_project_setting(name: String, default_value, type: int):
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	
	var info = {
		"name": name,
		"type": type,
		"hint": PROPERTY_HINT_NONE
	}
	ProjectSettings.add_property_info(info)
	ProjectSettings.set_initial_value(name, default_value)
