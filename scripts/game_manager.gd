class_name GameManager
extends Node

signal match_started(participants: Array[Entity])
signal match_finished(winner: Entity)
signal round_started(round_number: int)
signal turn_started(entity: Entity, participant_index: int, round_number: int, turn_number: int)
signal dice_rolled(entity: Entity, dice_values: Array[int])
signal roll_finished(
	entity: Entity,
	destination_index: int,
	participant_index: int,
	round_number: int,
	turn_number: int
)
signal turn_skipped(entity: Entity, reason: StringName)
signal turn_finished(
	entity: Entity,
	destination_index: int,
	participant_index: int,
	round_number: int,
	turn_number: int
)

enum MatchState {LOBBY, ACTIVE, FINISHED}

const MAX_PARTICIPANTS := 4

@export_category("Match")
@export var board: Board
@export var game_camera: GameCamera
## Ordered turn list. Invalid and duplicate entries are removed at match start.
@export var participants: Array[Entity] = []
@export_range(0, 1000, 1) var starting_plot_index := 0
@export var auto_start := true
@export var reset_entities_on_start := true
@export_category("AI")
@export var auto_play_ai := true
@export_range(0.0, 10.0, 0.1, "suffix:s") var ai_roll_delay := 0.75

var state := MatchState.LOBBY
var round_number := 0
var turn_number := 0
var active_participant_index := -1

var _turn_is_resolving := false
var _active_entity_has_rolled := false
var _last_destination_index := -1
var _turn_generation := 0


func _ready() -> void:
	if auto_start:
		call_deferred(&"start_match")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"roll_dice"):
		return
	if request_roll():
		get_viewport().set_input_as_handled()


func start_match() -> bool:
	if state == MatchState.ACTIVE:
		return false
	if not is_instance_valid(board):
		push_error("GameManager requires a valid Board before starting a match.")
		return false

	participants = _sanitize_participants(participants)
	if participants.is_empty():
		push_error("GameManager requires at least one valid participant.")
		return false

	for participant in participants:
		if reset_entities_on_start:
			participant.reset_for_match()
		if not participant.defeated.is_connected(_on_participant_defeated):
			participant.defeated.connect(_on_participant_defeated)
		board.register_entity(participant, starting_plot_index)

	state = MatchState.ACTIVE
	round_number = 1
	turn_number = 1
	active_participant_index = _find_next_eligible_index(-1)
	_turn_is_resolving = false
	_turn_generation += 1

	match_started.emit(participants)
	round_started.emit(round_number)
	_begin_current_turn()
	return true


func get_active_entity() -> Entity:
	if active_participant_index < 0 or active_participant_index >= participants.size():
		return null
	var entity := participants[active_participant_index]
	return entity if is_instance_valid(entity) else null


func is_turn_resolving() -> bool:
	return _turn_is_resolving


func has_active_entity_rolled() -> bool:
	return _active_entity_has_rolled


## Used by local input. Multiplayer authority can instead call play_active_turn()
## with validated dice values and replicate the result.
func request_roll(requesting_entity: Entity = null) -> bool:
	var active_entity := get_active_entity()
	if not _can_resolve_turn(active_entity):
		return false
	if requesting_entity != null and requesting_entity != active_entity:
		return false
	if active_entity.type == Entity.EntityType.AI and auto_play_ai:
		return false

	play_active_turn(active_entity.roll_dice())
	return true


## Resolves the active participant's roll. The turn remains active after physical
## movement and landing behaviour complete until request_end_turn() is called.
func play_active_turn(dice_values: Array[int]) -> int:
	var active_entity := get_active_entity()
	if not _can_resolve_turn(active_entity):
		return -1
	if not _are_valid_dice(dice_values):
		push_error("A turn requires exactly two dice values between 1 and 6.")
		return -1

	_turn_is_resolving = true
	_active_entity_has_rolled = true
	var resolving_index := active_participant_index
	var resolving_round := round_number
	var resolving_turn := turn_number
	var rolled_values := dice_values.duplicate()
	dice_rolled.emit(active_entity, rolled_values)

	var destination_index := await board.move_entity(active_entity, rolled_values)
	_turn_is_resolving = false
	_last_destination_index = destination_index
	roll_finished.emit(
		active_entity,
		destination_index,
		resolving_index,
		resolving_round,
		resolving_turn
	)

	return destination_index


## Ends a turn after its roll and movement have resolved. Human UI, AI logic,
## and future network authority all use the same validation path.
func request_end_turn(requesting_entity: Entity = null) -> bool:
	var active_entity := get_active_entity()
	if state != MatchState.ACTIVE or _turn_is_resolving:
		return false
	if not is_instance_valid(active_entity) or not _active_entity_has_rolled:
		return false
	if requesting_entity != null and requesting_entity != active_entity:
		return false

	turn_finished.emit(
		active_entity,
		_last_destination_index,
		active_participant_index,
		round_number,
		turn_number
	)
	_advance_turn()
	return true


func get_alive_participants() -> Array[Entity]:
	var alive: Array[Entity] = []
	for participant in participants:
		if is_instance_valid(participant) and not participant.is_defeated():
			alive.append(participant)
	return alive


func _begin_current_turn() -> void:
	var active_entity := get_active_entity()
	if not is_instance_valid(active_entity):
		_finish_match(null)
		return

	_turn_generation += 1
	_active_entity_has_rolled = false
	_last_destination_index = -1
	if is_instance_valid(game_camera):
		game_camera.focus_turn_target(active_entity)
	turn_started.emit(
		active_entity,
		active_participant_index,
		round_number,
		turn_number
	)

	if active_entity.type == Entity.EntityType.AI and auto_play_ai:
		_schedule_ai_turn(active_entity, _turn_generation)


func _advance_turn() -> void:
	var alive := get_alive_participants()
	if alive.size() <= 1:
		_finish_match(alive.front() if not alive.is_empty() else null)
		return

	var previous_index := active_participant_index
	var next_index := _find_next_eligible_index(previous_index)
	if next_index == -1:
		_finish_match(null)
		return

	active_participant_index = next_index
	turn_number += 1
	if next_index <= previous_index:
		round_number += 1
		round_started.emit(round_number)
	_begin_current_turn()


func _find_next_eligible_index(from_index: int) -> int:
	if participants.is_empty():
		return -1

	for offset in range(1, participants.size() + 1):
		var candidate_index := posmod(from_index + offset, participants.size())
		var candidate := participants[candidate_index]
		if is_instance_valid(candidate) and not candidate.is_defeated():
			return candidate_index
	return -1


func _finish_match(winner: Entity) -> void:
	state = MatchState.FINISHED
	_turn_is_resolving = false
	_active_entity_has_rolled = false
	_last_destination_index = -1
	_turn_generation += 1
	active_participant_index = -1
	match_finished.emit(winner)


func _schedule_ai_turn(expected_entity: Entity, generation: int) -> void:
	await get_tree().create_timer(ai_roll_delay).timeout
	if generation != _turn_generation:
		return
	if state != MatchState.ACTIVE or get_active_entity() != expected_entity:
		return
	if _turn_is_resolving or expected_entity.is_defeated():
		return
	await play_active_turn(expected_entity.roll_dice())
	if generation != _turn_generation:
		return
	request_end_turn(expected_entity)


func _on_participant_defeated(entity: Entity) -> void:
	if state != MatchState.ACTIVE or _turn_is_resolving:
		return

	var alive := get_alive_participants()
	if alive.size() <= 1:
		_finish_match(alive.front() if not alive.is_empty() else null)
	elif entity == get_active_entity():
		turn_skipped.emit(entity, &"defeated")
		_advance_turn()


func _can_resolve_turn(active_entity: Entity) -> bool:
	return (
		state == MatchState.ACTIVE
		and not _turn_is_resolving
		and not _active_entity_has_rolled
		and is_instance_valid(active_entity)
		and not active_entity.is_defeated()
		and is_instance_valid(board)
	)


func _are_valid_dice(dice_values: Array[int]) -> bool:
	if dice_values.size() != 2:
		return false
	for die_value in dice_values:
		if die_value < 1 or die_value > 6:
			return false
	return true


func _sanitize_participants(source: Array[Entity]) -> Array[Entity]:
	var sanitized: Array[Entity] = []
	var seen_ids: Dictionary[int, bool] = {}
	for participant in source:
		if not is_instance_valid(participant):
			continue
		var participant_id := participant.get_instance_id()
		if seen_ids.has(participant_id):
			continue
		if sanitized.size() == MAX_PARTICIPANTS:
			push_warning("GameManager supports at most four participants; extras were ignored.")
			break
		seen_ids[participant_id] = true
		sanitized.append(participant)
	return sanitized
