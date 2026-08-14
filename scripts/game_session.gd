extends Node

const SETTINGS_PATH := "user://settings.cfg"

## Menu selections that need to survive a scene change.
var participant_count := 4
var local_human_count := 1
var dev_options_enabled := false
var camera_follow_all_turns := true
var dynamic_camera_motion := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	dev_options_enabled = bool(config.get_value(
		"developer", "enabled", dev_options_enabled
	))
	camera_follow_all_turns = bool(config.get_value(
		"camera", "follow_all_turns", camera_follow_all_turns
	))
	dynamic_camera_motion = bool(config.get_value(
		"camera", "dynamic_movement", dynamic_camera_motion
	))


func set_dev_options_enabled(enabled: bool) -> void:
	dev_options_enabled = enabled
	save_settings()


func set_camera_follow_all_turns(enabled: bool) -> void:
	camera_follow_all_turns = enabled
	save_settings()


func set_dynamic_camera_motion(enabled: bool) -> void:
	dynamic_camera_motion = enabled
	save_settings()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("developer", "enabled", dev_options_enabled)
	config.set_value("camera", "follow_all_turns", camera_follow_all_turns)
	config.set_value("camera", "dynamic_movement", dynamic_camera_motion)
	config.save(SETTINGS_PATH)
