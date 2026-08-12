extends Control

const GAME_SCENE := "res://play_scenes/test_scene.tscn"

@onready var main_panel: PanelContainer = %MainPanel
@onready var player_setup_panel: PanelContainer = %PlayerSetupPanel
@onready var game_session := get_node("/root/GameSession")
@onready var player_count_buttons: Array[Button] = [
	%TwoPlayersButton,
	%ThreePlayersButton,
	%FourPlayersButton,
]

var selected_player_count := 4


func _ready() -> void:
	%NewGameButton.pressed.connect(_show_player_setup)
	%BackButton.pressed.connect(_show_main_menu)
	%StartGameButton.pressed.connect(_start_game)

	for index in player_count_buttons.size():
		player_count_buttons[index].pressed.connect(
			_select_player_count.bind(index + 2)
		)

	_select_player_count(int(game_session.get("participant_count")))
	%NewGameButton.grab_focus()


func _show_player_setup() -> void:
	main_panel.hide()
	player_setup_panel.show()
	player_count_buttons[selected_player_count - 2].grab_focus()


func _show_main_menu() -> void:
	player_setup_panel.hide()
	main_panel.show()
	%NewGameButton.grab_focus()


func _select_player_count(player_count: int) -> void:
	selected_player_count = clampi(player_count, 2, 4)
	for index in player_count_buttons.size():
		var button := player_count_buttons[index]
		var is_selected := index + 2 == selected_player_count
		button.button_pressed = is_selected
		button.text = "%d Players%s" % [
			index + 2,
			"  [Selected]" if is_selected else "",
		]


func _start_game() -> void:
	game_session.set("participant_count", selected_player_count)
	get_tree().change_scene_to_file(GAME_SCENE)
