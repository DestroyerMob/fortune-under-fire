class_name TurnCameraController
extends Node

## Keeps camera policy out of authoritative match state. Event holds in
## GameCamera automatically queue this target until their presentation ends.
var _game_camera: GameCamera


func configure(game_manager: GameManager, game_camera: GameCamera) -> void:
	_game_camera = game_camera
	game_manager.turn_started.connect(_on_turn_started)


func _on_turn_started(
	entity: Entity,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	_game_camera.focus_turn_target(entity)
