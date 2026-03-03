@tool
extends Control

@onready var status_label = $VBoxContainer/StatusLabel

func _on_test_connection_pressed():
	var tid = ProjectSettings.get_setting("glitch/config/title_id", "")
	if tid == "":
		status_label.text = "Error: No Title ID set in Project Settings!"
		return
	
	status_label.text = "Connecting to Glitch..."
	# Logic to ping the API and update the label to "Connected"

func _on_test_connection_pressed():
	var tid = ProjectSettings.get_setting("glitch/config/title_id", "")
	var token = ProjectSettings.get_setting("glitch/config/title_token", "")
	
	if tid == "" or token == "":
		status_label.text = "Error: Missing ID or Token in Project Settings!"
		return
	
	status_label.text = "Connecting to Glitch..."
	
	var http = HTTPRequest.new()
	add_child(http)
	
	# We ping the public title view to verify the ID and Token
	var url = "https://api.glitch.fun/api/titles/%s" % tid
	var headers = ["Authorization: Bearer " + token]
	
	http.request(url, headers, HTTPClient.METHOD_GET)
	var response = await http.request_completed
	var code = response[1]
	
	if code == 200:
		status_label.text = "Status: Connected to Glitch!"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		status_label.text = "Status: Connection Failed (Code %d)" % code
		status_label.add_theme_color_override("font_color", Color.RED)
	
	http.queue_free()
