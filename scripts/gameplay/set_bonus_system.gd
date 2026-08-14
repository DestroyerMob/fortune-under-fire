class_name SetBonusSystem
extends Node

## Authoritative owner of complete-property-set powers. It derives control from
## Board/Plot state, while retaining only consumable per-turn/per-lap state.
signal complete_sets_changed(entity: Entity, controlled_sets: Array[PropertyGroupData])
signal charge_changed(entity: Entity, group: PropertyGroupData, charges: int)
signal bonus_triggered(
	entity: Entity,
	group: PropertyGroupData,
	amount: int,
	context: StringName
)

var _board: Board
var _participants: Array[Entity] = []
var _known_control: Dictionary[int, Dictionary] = {}
var _turn_uses: Dictionary[String, bool] = {}
var _charges: Dictionary[String, int] = {}
var _tribute_claims: Dictionary[String, bool] = {}


func configure(board: Board, participants: Array[Entity]) -> void:
	_board = board
	_participants = participants.duplicate()
	for plot in _board.plots:
		var callback := _on_plot_owner_changed.bind(plot)
		if not plot.owner_changed.is_connected(callback):
			plot.owner_changed.connect(callback)
	if not _board.past_start.is_connected(_on_past_start):
		_board.past_start.connect(_on_past_start)
	reset_for_match(participants)


func reset_for_match(participants: Array[Entity]) -> void:
	_participants = participants.duplicate()
	_known_control.clear()
	_turn_uses.clear()
	_charges.clear()
	_tribute_claims.clear()
	for participant in _participants:
		_refresh_control(participant, false)


func begin_turn(entity: Entity) -> void:
	if not is_instance_valid(entity):
		return
	var prefix := "%d:" % entity.get_instance_id()
	for key in _turn_uses.keys():
		if String(key).begins_with(prefix):
			_turn_uses.erase(key)


func get_complete_sets(entity: Entity) -> Array[PropertyGroupData]:
	var complete_sets: Array[PropertyGroupData] = []
	if not is_instance_valid(entity) or not is_instance_valid(_board):
		return complete_sets
	for group in _get_property_groups():
		if owns_complete_set(entity, group):
			complete_sets.append(group)
	return complete_sets


func owns_complete_set(entity: Entity, group: PropertyGroupData) -> bool:
	if not is_instance_valid(entity) or group == null or not is_instance_valid(_board):
		return false
	var group_plots := _get_group_plots(group)
	if group_plots.size() != group.complete_set_size:
		return false
	for plot in group_plots:
		if plot.plot_owner != entity:
			return false
	return true


func controls_bonus(
	entity: Entity,
	bonus: PropertyGroupData.ControlBonus
) -> bool:
	return get_controlled_group(entity, bonus) != null


func get_controlled_group(
	entity: Entity,
	bonus: PropertyGroupData.ControlBonus
) -> PropertyGroupData:
	for group in get_complete_sets(entity):
		if group.control_bonus == bonus:
			return group
	return null


func get_group_progress(entity: Entity, group: PropertyGroupData) -> Vector2i:
	var owned := 0
	var group_plots := _get_group_plots(group)
	for plot in group_plots:
		if plot.plot_owner == entity:
			owned += 1
	return Vector2i(owned, group_plots.size())


func get_construction_cost(entity: Entity, base_cost: int) -> int:
	var group := get_controlled_group(
		entity,
		PropertyGroupData.ControlBonus.INDUSTRIAL_EFFICIENCY
	)
	if group == null or _has_turn_use(entity, group.control_bonus):
		return base_cost
	return maxi(
		base_cost - int(roundi(float(base_cost * group.control_bonus_value) / 100.0)),
		0
	)


func commit_construction_discount(entity: Entity, base_cost: int, paid_cost: int) -> void:
	if paid_cost >= base_cost:
		return
	var group := get_controlled_group(
		entity,
		PropertyGroupData.ControlBonus.INDUSTRIAL_EFFICIENCY
	)
	if group == null:
		return
	_mark_turn_use(entity, group.control_bonus)
	bonus_triggered.emit(entity, group, base_cost - paid_cost, &"construction_discount")


func can_adjust_movement(entity: Entity) -> bool:
	var group := get_controlled_group(
		entity,
		PropertyGroupData.ControlBonus.GUIDED_CURRENT
	)
	return group != null and not _has_turn_use(entity, group.control_bonus)


func consume_movement_adjustment(entity: Entity, adjustment: int) -> bool:
	var group := get_controlled_group(
		entity,
		PropertyGroupData.ControlBonus.GUIDED_CURRENT
	)
	if (
		group == null
		or _has_turn_use(entity, group.control_bonus)
		or absi(adjustment) > group.control_bonus_value
	):
		return false
	_mark_turn_use(entity, group.control_bonus)
	bonus_triggered.emit(entity, group, adjustment, &"movement_adjustment")
	return true


func modify_outgoing_damage(owner: Entity, damage: int) -> int:
	var group := get_controlled_group(
		owner,
		PropertyGroupData.ControlBonus.OVERCHARGE
	)
	if group == null or get_charges(owner, group) <= 0 or damage <= 0:
		return damage
	_set_charges(owner, group, 0)
	var bonus_damage := int(ceili(float(damage * group.control_bonus_value) / 100.0))
	bonus_triggered.emit(owner, group, bonus_damage, &"overcharge")
	return damage + bonus_damage


func modify_incoming_damage(target: Entity, damage: int) -> int:
	var group := get_controlled_group(
		target,
		PropertyGroupData.ControlBonus.LIVING_WARD
	)
	if group == null or get_charges(target, group) <= 0 or damage <= 0:
		return damage
	_set_charges(target, group, 0)
	var prevented := mini(
		int(ceili(float(damage * group.control_bonus_value) / 100.0)),
		damage
	)
	bonus_triggered.emit(target, group, prevented, &"ward")
	return damage - prevented


func consume_tribute(owner: Entity, payer: Entity, payment: int) -> int:
	var group := get_controlled_group(owner, PropertyGroupData.ControlBonus.TRIBUTE)
	if group == null or payment <= 0 or not is_instance_valid(payer):
		return 0
	var claim_key := "%d:%d" % [owner.get_instance_id(), payer.get_instance_id()]
	if _tribute_claims.has(claim_key):
		return 0
	_tribute_claims[claim_key] = true
	var tribute := int(roundi(float(payment * group.control_bonus_value) / 100.0))
	if tribute > 0:
		bonus_triggered.emit(owner, group, tribute, &"tribute")
	return tribute


func get_charges(entity: Entity, group: PropertyGroupData) -> int:
	if not is_instance_valid(entity) or group == null:
		return 0
	return _charges.get(_state_key(entity, group.control_bonus), 0)


func _on_past_start(entity: Entity) -> void:
	if not is_instance_valid(entity):
		return
	var tribute_prefix := "%d:" % entity.get_instance_id()
	for claim_key in _tribute_claims.keys():
		if String(claim_key).begins_with(tribute_prefix):
			_tribute_claims.erase(claim_key)
	for group in get_complete_sets(entity):
		if group.control_bonus in [
			PropertyGroupData.ControlBonus.LIVING_WARD,
			PropertyGroupData.ControlBonus.SOVEREIGN_CLAIM,
			PropertyGroupData.ControlBonus.OVERCHARGE,
			PropertyGroupData.ControlBonus.MASTERWORK_COMMISSION,
		]:
			_set_charges(entity, group, 1)


func _on_plot_owner_changed(
	previous_owner: Entity,
	current_owner: Entity,
	_plot: Plot
) -> void:
	_refresh_control(previous_owner)
	_refresh_control(current_owner)


func _refresh_control(entity: Entity, publish := true) -> void:
	if not is_instance_valid(entity):
		return
	var entity_id := entity.get_instance_id()
	var previous: Dictionary = _known_control.get(entity_id, {})
	var current: Dictionary = {}
	var complete_sets := get_complete_sets(entity)
	for group in complete_sets:
		current[group.group_id] = true
		if not previous.has(group.group_id) and group.control_bonus in [
			PropertyGroupData.ControlBonus.LIVING_WARD,
			PropertyGroupData.ControlBonus.SOVEREIGN_CLAIM,
			PropertyGroupData.ControlBonus.OVERCHARGE,
			PropertyGroupData.ControlBonus.MASTERWORK_COMMISSION,
		]:
			_set_charges(entity, group, 1)
	for old_group_id in previous.keys():
		if current.has(old_group_id):
			continue
		var old_group := _find_group(old_group_id)
		if old_group != null:
			_set_charges(entity, old_group, 0)
	_known_control[entity_id] = current
	if publish and previous != current:
		complete_sets_changed.emit(entity, complete_sets)


func _set_charges(entity: Entity, group: PropertyGroupData, value: int) -> void:
	var key := _state_key(entity, group.control_bonus)
	var clamped := maxi(value, 0)
	if int(_charges.get(key, 0)) == clamped:
		return
	_charges[key] = clamped
	charge_changed.emit(entity, group, clamped)


func _has_turn_use(
	entity: Entity,
	bonus: PropertyGroupData.ControlBonus
) -> bool:
	return _turn_uses.has(_state_key(entity, bonus))


func _mark_turn_use(
	entity: Entity,
	bonus: PropertyGroupData.ControlBonus
) -> void:
	_turn_uses[_state_key(entity, bonus)] = true


func _state_key(entity: Entity, bonus: PropertyGroupData.ControlBonus) -> String:
	return "%d:%d" % [entity.get_instance_id(), int(bonus)]


func _get_property_groups() -> Array[PropertyGroupData]:
	var groups: Array[PropertyGroupData] = []
	if not is_instance_valid(_board):
		return groups
	for plot in _board.plots:
		if plot.data == null or plot.data.property_group == null:
			continue
		if not groups.has(plot.data.property_group):
			groups.append(plot.data.property_group)
	return groups


func _get_group_plots(group: PropertyGroupData) -> Array[Plot]:
	var group_plots: Array[Plot] = []
	if group == null or not is_instance_valid(_board):
		return group_plots
	for plot in _board.plots:
		if plot.data != null and plot.data.property_group == group:
			group_plots.append(plot)
	return group_plots


func _find_group(group_id: StringName) -> PropertyGroupData:
	for group in _get_property_groups():
		if group.group_id == group_id:
			return group
	return null
