class_name GameplayFeedbackController
extends Node

## Translates authoritative outcomes into local visual choreography. It never
## changes money, health, property state, or turn state.
const EVENT_CAMERA_HOLD_SECONDS := 1.0

var _game_manager: GameManager
var _game_camera: GameCamera


func configure(game_manager: GameManager, game_camera: GameCamera) -> void:
	_game_manager = game_manager
	_game_camera = game_camera
	_game_manager.rent_paid.connect(_on_rent_paid)
	_game_manager.start_income_awarded.connect(_on_start_income_awarded)
	_game_manager.building_effect_resolved.connect(_on_building_effect_resolved)


func _on_rent_paid(
	payer: Entity,
	owner: Entity,
	_plot: Plot,
	amount: int
) -> void:
	if amount <= 0:
		return
	if is_instance_valid(owner):
		owner.play_money_feedback(amount, "RENT")
	if is_instance_valid(payer):
		payer.play_money_feedback(-amount, "RENT")
		_game_camera.hold_event_target(payer, EVENT_CAMERA_HOLD_SECONDS)


func _on_start_income_awarded(entity: Entity, amount: int) -> void:
	if is_instance_valid(entity) and amount > 0:
		entity.play_money_feedback(amount, "LAP")


func _on_building_effect_resolved(activation: BuildingActivation) -> void:
	if is_instance_valid(activation.source_plot):
		activation.source_plot.play_building_activation()
	if not is_instance_valid(activation.target):
		return
	if activation.kind == BuildingActivation.EffectKind.DAMAGE:
		activation.target.play_damage_feedback(activation.amount)
		_game_camera.hold_event_target(
			activation.target,
			EVENT_CAMERA_HOLD_SECONDS
		)
	elif activation.kind == BuildingActivation.EffectKind.HEALING:
		activation.target.play_healing_feedback(activation.amount)
		_game_camera.hold_event_target(
			activation.target,
			EVENT_CAMERA_HOLD_SECONDS
		)
