extends Node

# This script runs automatically as an Autoload
var title_id: String = ""
var title_token: String = ""
var install_id: String = ""
var is_active: bool = false

func _ready():
	# 1. Load settings from Project Settings
	title_id = ProjectSettings.get_setting("glitch/config/title_id", "")
	title_token = ProjectSettings.get_setting("glitch/config/title_token", "")
	var auto_start = ProjectSettings.get_setting("glitch/config/auto_start_handshake", true)
	
	if title_id == "" or title_token == "":
		push_warning("Glitch Aegis: Title ID or Token missing in Project Settings.")
		return

	if auto_start:
		initialize_glitch()

func initialize_glitch():
	# Detect Install ID from Web URL or Command Line
	if OS.has_feature("web"):
		install_id = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('install_id')")
	
	if install_id == null or install_id == "":
		# Fallback for local testing
		install_id = "dev_test_user"
		
	_perform_handshake()

func _perform_handshake():
	var url = "https://api.glitch.fun/api/titles/%s/installs/%s/validate" % [title_id, install_id]
	var http = HTTPRequest.new()
	add_child(http)
	
	var headers = ["Authorization: Bearer " + title_token, "Accept: application/json"]
	http.request(url, headers, HTTPClient.METHOD_POST)
	
	var response = await http.request_completed
	var code = response[1]
	
	if code == 200:
		print("Glitch Aegis: Handshake Successful. Payouts Enabled.")
		_start_payout_timer()
	else:
		print("Glitch Aegis: Handshake Failed. Code: ", code)
	
	http.queue_free()

func _start_payout_timer():
	is_active = true
	var timer = Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.timeout.connect(_send_heartbeat)
	add_child(timer)
	_send_heartbeat()

func _send_heartbeat():
	if not is_active: return
	
	var url = "https://api.glitch.fun/api/titles/%s/installs" % title_id
	var http = HTTPRequest.new()
	add_child(http)
	
	var data = {
		"user_install_id": install_id,
		"platform": OS.get_name().to_lower(),
		"fingerprint_components": _get_fingerprint()
	}
	
	var headers = ["Authorization: Bearer " + title_token, "Content-Type: application/json"]
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))
	
	await http.request_completed
	http.queue_free()

func _get_fingerprint() -> Dictionary:
	return {
		"os": {"name": OS.get_name(), "version": OS.get_version()},
		"hardware": {"cpu": OS.get_processor_name(), "cores": OS.get_processor_count()}
	}
