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
