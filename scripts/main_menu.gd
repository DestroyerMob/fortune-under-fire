extends Control

const GAME_SCENE := "res://play_scenes/test_scene.tscn"

@onready var main_panel: PanelContainer = %MainPanel
@onready var player_setup_panel: PanelContainer = %PlayerSetupPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var game_session := get_node("/root/GameSession")
@onready var player_count_buttons: Array[Button] = [
	%TwoPlayersButton,
	%ThreePlayersButton,
	%FourPlayersButton,
]

var selected_player_count := 4
var selected_human_count := 1


func _ready() -> void:
	%NewGameButton.pressed.connect(_show_player_setup)
	%SettingsButton.pressed.connect(_show_settings)
	%QuitButton.pressed.connect(_quit_game)
	%BackButton.pressed.connect(_show_main_menu)
	%SettingsBackButton.pressed.connect(_show_main_menu)
	%StartGameButton.pressed.connect(_start_game)
	%FewerHumansButton.pressed.connect(_change_human_count.bind(-1))
	%MoreHumansButton.pressed.connect(_change_human_count.bind(1))

	for index in player_count_buttons.size():
		player_count_buttons[index].pressed.connect(
			_select_player_count.bind(index + 2)
		)

	selected_human_count = clampi(
		int(game_session.get("local_human_count")),
		1,
		GameManager.MAX_PARTICIPANTS
	)
	_select_player_count(int(game_session.get("participant_count")))
	%FollowAllTurnsCheck.button_pressed = bool(
		game_session.get("camera_follow_all_turns")
	)
	%DynamicCameraCheck.button_pressed = bool(
		game_session.get("dynamic_camera_motion")
	)
	%DevOptionsCheck.button_pressed = bool(
		game_session.get("dev_options_enabled")
	)
	_refresh_dev_settings()
	%FollowAllTurnsCheck.toggled.connect(_on_follow_all_turns_toggled)
	%DynamicCameraCheck.toggled.connect(_on_dynamic_camera_toggled)
	%DevOptionsCheck.toggled.connect(_on_dev_options_toggled)
	%NewGameButton.grab_focus()
	_animate_panel_in(main_panel)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if player_setup_panel.visible or settings_panel.visible:
		_show_main_menu()
		get_viewport().set_input_as_handled()


func _show_player_setup() -> void:
	main_panel.hide()
	settings_panel.hide()
	player_setup_panel.show()
	_animate_panel_in(player_setup_panel)
	player_count_buttons[selected_player_count - 2].grab_focus()


func _show_main_menu() -> void:
	player_setup_panel.hide()
	settings_panel.hide()
	main_panel.show()
	_animate_panel_in(main_panel)
	%NewGameButton.grab_focus()


func _show_settings() -> void:
	main_panel.hide()
	player_setup_panel.hide()
	settings_panel.show()
	_refresh_dev_settings()
	_animate_panel_in(settings_panel)
	%FollowAllTurnsCheck.grab_focus()


func _on_follow_all_turns_toggled(enabled: bool) -> void:
	game_session.set_camera_follow_all_turns(enabled)


func _on_dynamic_camera_toggled(enabled: bool) -> void:
	game_session.set_dynamic_camera_motion(enabled)


func _on_dev_options_toggled(enabled: bool) -> void:
	game_session.set_dev_options_enabled(enabled)
	_refresh_dev_settings()


func _refresh_dev_settings() -> void:
	%DevShortcutPanel.visible = %DevOptionsCheck.button_pressed


func _quit_game() -> void:
	get_tree().quit()


func _select_player_count(player_count: int) -> void:
	selected_player_count = clampi(player_count, 2, 4)
	selected_human_count = mini(selected_human_count, selected_player_count)
	for index in player_count_buttons.size():
		var button := player_count_buttons[index]
		var is_selected := index + 2 == selected_player_count
		button.button_pressed = is_selected
		button.text = "%d\nPLAYERS" % (index + 2)
	_refresh_seat_mix()


func _change_human_count(direction: int) -> void:
	selected_human_count = clampi(
		selected_human_count + direction,
		1,
		selected_player_count
	)
	_refresh_seat_mix()


func _refresh_seat_mix() -> void:
	var ai_count := selected_player_count - selected_human_count
	%HumanCountValue.text = "%d" % selected_human_count
	%FewerHumansButton.disabled = selected_human_count <= 1
	%MoreHumansButton.disabled = selected_human_count >= selected_player_count
	%SelectionSummary.text = "%d local %s  ·  %s" % [
		selected_human_count,
		"human" if selected_human_count == 1 else "humans",
		"no bots" if ai_count == 0 else "%d AI" % ai_count,
	]
	%StartGameButton.text = (
		"Start Hot-Seat Match"
		if selected_human_count > 1
		else "Start Game"
	)


func _animate_panel_in(panel: Control) -> void:
	panel.pivot_offset = panel.size * 0.5
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.975, 0.975)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, ^"modulate:a", 1.0, 0.18)
	tween.tween_property(panel, ^"scale", Vector2.ONE, 0.18)


func _start_game() -> void:
	game_session.set("participant_count", selected_player_count)
	game_session.set("local_human_count", selected_human_count)
	get_tree().change_scene_to_file(GAME_SCENE)
