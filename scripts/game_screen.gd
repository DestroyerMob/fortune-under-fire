extends Node3D

@onready var game_manager: GameManager = $GameManager
@onready var local_player: Entity = $Player
@onready var available_participants: Array[Entity] = [
	$Player,
	$Player2,
	$Player3,
	$Player4,
]
@onready var turn_label: Label = %TurnLabel
@onready var roll_result_label: Label = %RollResultLabel
@onready var hint_label: Label = %HintLabel
@onready var roll_button: Button = %RollButton
@onready var end_turn_button: Button = %EndTurnButton


func _ready() -> void:
	_configure_participants()
	_connect_game_signals()
	roll_button.pressed.connect(_on_roll_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	game_manager.start_match()
	_update_action_controls()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().change_scene_to_file("res://play_scenes/main_menu.tscn")
		get_viewport().set_input_as_handled()


func _configure_participants() -> void:
	var game_session := get_node("/root/GameSession")
	var participant_count := clampi(
		int(game_session.get("participant_count")),
		2,
		4
	)
	var configured_participants: Array[Entity] = []

	for index in available_participants.size():
		var participant := available_participants[index]
		var is_participating := index < participant_count
		participant.visible = is_participating
		participant.type = Entity.EntityType.PLAYER if index == 0 else Entity.EntityType.AI
		if is_participating:
			configured_participants.append(participant)

	game_manager.participants = configured_participants


func _connect_game_signals() -> void:
	game_manager.turn_started.connect(_on_turn_started)
	game_manager.dice_rolled.connect(_on_dice_rolled)
	game_manager.roll_finished.connect(_on_roll_finished)
	game_manager.turn_finished.connect(_on_turn_finished)
	game_manager.match_finished.connect(_on_match_finished)


func _on_roll_pressed() -> void:
	if game_manager.request_roll(local_player):
		hint_label.text = "Moving your piece..."
		_update_action_controls()


func _on_end_turn_pressed() -> void:
	hint_label.text = "Ending your turn..."
	if game_manager.request_end_turn(local_player):
		_update_action_controls()


func _on_turn_started(
	entity: Entity,
	participant_index: int,
	round_number: int,
	_turn_number: int
) -> void:
	var participant_name := _get_participant_name(entity, participant_index)
	turn_label.text = (
		"Round %d  |  Your Turn" % round_number
		if entity == local_player
		else "Round %d  |  %s's Turn" % [round_number, participant_name]
	)
	roll_result_label.text = "No roll yet"
	if entity == local_player:
		hint_label.text = "Roll the dice, then end your turn. (Space also rolls.)"
	else:
		hint_label.text = "%s is thinking..." % participant_name
	_update_action_controls()


func _on_dice_rolled(entity: Entity, dice_values: Array[int]) -> void:
	var participant_index := game_manager.participants.find(entity)
	roll_result_label.text = "%s rolled %d + %d = %d" % [
		_get_participant_name(entity, participant_index),
		dice_values[0],
		dice_values[1],
		dice_values[0] + dice_values[1],
	]
	_update_action_controls()


func _on_roll_finished(
	entity: Entity,
	_destination_index: int,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	if entity == local_player:
		hint_label.text = "Movement complete. End your turn when ready."
	else:
		hint_label.text = "%s is ending their turn..." % _get_participant_name(
			entity,
			game_manager.participants.find(entity)
		)
	_update_action_controls()


func _on_turn_finished(
	_entity: Entity,
	_destination_index: int,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	_update_action_controls()


func _on_match_finished(winner: Entity) -> void:
	turn_label.text = "Match Complete"
	roll_result_label.text = (
		(
			"You win!"
			if winner == local_player
			else "%s wins!" % _get_participant_name(
				winner,
				game_manager.participants.find(winner)
			)
		)
		if is_instance_valid(winner)
		else "The match ended without a winner."
	)
	hint_label.text = "Press Esc to return to the main menu."
	_update_action_controls()


func _update_action_controls() -> void:
	var active_entity := game_manager.get_active_entity()
	var is_local_turn := active_entity == local_player
	var is_resolving := game_manager.is_turn_resolving()
	var has_rolled := game_manager.has_active_entity_rolled()
	roll_button.disabled = not is_local_turn or is_resolving or has_rolled
	end_turn_button.disabled = not is_local_turn or is_resolving or not has_rolled


func _get_participant_name(entity: Entity, participant_index: int) -> String:
	if entity == local_player:
		return "You"
	if participant_index >= 0:
		return "AI %d" % participant_index
	return "Unknown player"
