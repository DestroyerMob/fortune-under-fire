class_name SetBonusHudController
extends Node

## Compact local presentation for controlled-set powers. It only submits the
## Guided Current choice; complete-set detection and use tracking stay in rules.
var _game_manager: GameManager
var _local_player: Entity
var _summary_panel: PanelContainer
var _summary_label: Label
var _choice_panel: PanelContainer
var _choice_details: Label
var _minus_button: Button
var _normal_button: Button
var _plus_button: Button
var _event_tween: Tween


func configure(
	game_manager: GameManager,
	local_player: Entity,
	summary_panel: PanelContainer,
	summary_label: Label,
	choice_panel: PanelContainer,
	choice_details: Label,
	minus_button: Button,
	normal_button: Button,
	plus_button: Button
) -> void:
	_game_manager = game_manager
	_local_player = local_player
	_summary_panel = summary_panel
	_summary_label = summary_label
	_choice_panel = choice_panel
	_choice_details = choice_details
	_minus_button = minus_button
	_normal_button = normal_button
	_plus_button = plus_button
	_minus_button.pressed.connect(_submit_adjustment.bind(-1))
	_normal_button.pressed.connect(_submit_adjustment.bind(0))
	_plus_button.pressed.connect(_submit_adjustment.bind(1))
	_game_manager.complete_sets_changed.connect(_on_complete_sets_changed)
	_game_manager.set_bonus_charge_changed.connect(_on_charge_changed)
	_game_manager.set_bonus_triggered.connect(_on_bonus_triggered)
	_game_manager.movement_adjustment_required.connect(_on_adjustment_required)
	_game_manager.movement_adjustment_resolved.connect(_on_adjustment_resolved)
	_game_manager.turn_started.connect(_on_turn_started)
	_game_manager.match_finished.connect(_on_match_finished)
	_choice_panel.hide()
	refresh_summary()


func set_local_player(local_player: Entity) -> void:
	_local_player = local_player
	_choice_panel.hide()
	refresh_summary()


func refresh_summary() -> void:
	var controlled_sets := _game_manager.get_complete_property_sets(_local_player)
	_summary_panel.visible = not controlled_sets.is_empty()
	if controlled_sets.is_empty():
		_summary_label.text = ""
		return
	var summaries: Array[String] = []
	for group in controlled_sets:
		var summary := group.control_bonus_name
		var charges := _game_manager.set_bonus_system.get_charges(
			_local_player,
			group
		)
		if group.control_bonus in [
			PropertyGroupData.ControlBonus.LIVING_WARD,
			PropertyGroupData.ControlBonus.SOVEREIGN_CLAIM,
			PropertyGroupData.ControlBonus.OVERCHARGE,
			PropertyGroupData.ControlBonus.MASTERWORK_COMMISSION,
		]:
			summary += "  %d/1" % charges
		summaries.append(summary)
	_summary_label.text = "  ·  ".join(summaries)


func _on_adjustment_required(
	entity: Entity,
	dice_values: Array[int],
	maximum_adjustment: int
) -> void:
	if entity != _local_player or dice_values.size() != 2:
		return
	var total := dice_values[0] + dice_values[1]
	_choice_details.text = "Rolled %d. Choose your movement total." % total
	_minus_button.text = "−%d\nMOVE %d" % [maximum_adjustment, total - maximum_adjustment]
	_normal_button.text = "KEEP\nMOVE %d" % total
	_plus_button.text = "+%d\nMOVE %d" % [maximum_adjustment, total + maximum_adjustment]
	_choice_panel.show()


func _submit_adjustment(adjustment: int) -> void:
	if _game_manager.request_movement_adjustment(_local_player, adjustment):
		_choice_panel.hide()


func _on_adjustment_resolved(
	entity: Entity,
	_adjustment: int,
	_movement_total: int
) -> void:
	if entity == _local_player:
		_choice_panel.hide()
		refresh_summary()


func _on_complete_sets_changed(
	entity: Entity,
	_controlled_sets: Array[PropertyGroupData]
) -> void:
	if entity == _local_player:
		refresh_summary()


func _on_charge_changed(
	entity: Entity,
	_group: PropertyGroupData,
	_charges: int
) -> void:
	if entity == _local_player:
		refresh_summary()


func _on_bonus_triggered(
	entity: Entity,
	group: PropertyGroupData,
	amount: int,
	context: StringName
) -> void:
	if entity != _local_player or context == &"movement_adjustment":
		return
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_summary_panel.show()
	_summary_label.modulate = group.color.lightened(0.34)
	match context:
		&"construction_discount":
			_summary_label.text = "%s  ·  SAVED $%d" % [group.control_bonus_name, amount]
		&"ward":
			_summary_label.text = "%s  ·  BLOCKED %d" % [group.control_bonus_name, amount]
		&"overcharge":
			_summary_label.text = "%s  ·  +%d DAMAGE" % [group.control_bonus_name, amount]
		&"tribute":
			_summary_label.text = "%s  ·  +$%d" % [group.control_bonus_name, amount]
		_:
			_summary_label.text = group.control_bonus_name
	_event_tween = create_tween().bind_node(_summary_label)
	_event_tween.tween_property(_summary_label, ^"modulate", Color.WHITE, 0.45)
	_event_tween.tween_interval(0.75)
	_event_tween.tween_callback(
		func() -> void:
			_event_tween = null
			refresh_summary()
	)


func _on_turn_started(
	_entity: Entity,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	_choice_panel.hide()
	refresh_summary()


func _on_match_finished(_winner: Entity) -> void:
	_choice_panel.hide()
	refresh_summary()
