class_name LocalSeatController
extends Node

signal presented_player_changed(player: Entity)

## Identifies the human seat whose turn is active. It does not advance turns or
## alter participants; GameScreen uses the signal to rebind local presentation.
var _game_manager: GameManager


func configure(game_manager: GameManager) -> void:
	_game_manager = game_manager
	_game_manager.turn_started.connect(_on_turn_started)


func _on_turn_started(
	entity: Entity,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	if not is_instance_valid(entity) or entity.type != Entity.EntityType.PLAYER:
		return

	presented_player_changed.emit(entity)
