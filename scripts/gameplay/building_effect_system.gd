class_name BuildingEffectSystem
extends Node

## Resolves all base-building effects. Board owns route facts and movement; this
## system asks Board for those facts but is the sole owner of activation rules.
signal activation_resolved(activation: BuildingActivation)

var _board: Board
var _set_bonus_system: SetBonusSystem
var _rng := RandomNumberGenerator.new()


func configure(board: Board) -> void:
	_board = board
	_rng.randomize()


func set_set_bonus_system(set_bonus_system: SetBonusSystem) -> void:
	_set_bonus_system = set_bonus_system


## Resolves buildings that activate when their owner completes a lap and returns
## the total building-only bonus. Base property income belongs to the economy.
func activate_lap(owner: Entity, owned_properties: Array[Plot]) -> int:
	var total_bonus := 0
	for plot in owned_properties:
		if not is_instance_valid(plot) or plot.building == null:
			continue
		var building_income := 0
		var die_roll := 0
		match plot.building.type:
			BuildingData.BuildingType.APARTMENTS:
				building_income = plot.building.money_value
			BuildingData.BuildingType.CASINO:
				die_roll = _rng.randi_range(1, 6)
				building_income = plot.building.money_value * die_roll
			BuildingData.BuildingType.BANK:
				var interest := plot.credit_bank_interest()
				if interest > 0:
					activation_resolved.emit(BuildingActivation.new(
						BuildingActivation.EffectKind.BANK_INTEREST,
						owner,
						plot,
						plot.building,
						null,
						interest
					))
				continue
		if building_income <= 0:
			continue
		total_bonus += building_income
		activation_resolved.emit(BuildingActivation.new(
			BuildingActivation.EffectKind.LAP_INCOME,
			owner,
			plot,
			plot.building,
			null,
			building_income,
			die_roll
		))
	return total_bonus


## Resolves every building that reacts to an entity reaching a destination.
func activate_landing(entity: Entity, landed_plot: Plot) -> void:
	if (
		not is_instance_valid(_board)
		or not is_instance_valid(entity)
		or not is_instance_valid(landed_plot)
	):
		return

	var landed_owner := landed_plot.plot_owner
	if (
		landed_owner == entity
		and landed_plot.has_building_type(BuildingData.BuildingType.MEDIC_TOWER)
	):
		var healed_amount := entity.heal(landed_plot.building.healing)
		if healed_amount > 0:
			activation_resolved.emit(BuildingActivation.new(
				BuildingActivation.EffectKind.HEALING,
				entity,
				landed_plot,
				landed_plot.building,
				entity,
				healed_amount
			))

	if is_instance_valid(landed_owner) and landed_owner != entity:
		if landed_plot.has_building_type(BuildingData.BuildingType.GUN_TOWER):
			_apply_damage(
				landed_owner,
				landed_plot,
				entity,
				landed_plot.building.damage
			)
		elif landed_plot.has_building_type(BuildingData.BuildingType.TESLA_COIL):
			_apply_damage(
				landed_owner,
				landed_plot,
				entity,
				landed_plot.building.damage
					* _get_connected_tesla_count(landed_plot, landed_owner)
			)

	# Artillery supports any nearby property belonging to the battery owner.
	if not is_instance_valid(landed_owner) or landed_owner == entity:
		return
	for source_plot in _board.plots:
		if (
			source_plot.plot_owner != landed_owner
			or not source_plot.has_building_type(
				BuildingData.BuildingType.ARTILLERY_BATTERY
			)
		):
			continue
		var route_distance := _board.get_route_distance(source_plot, landed_plot)
		if route_distance >= 0 and route_distance <= source_plot.building.range_spaces:
			_apply_damage(
				landed_owner,
				source_plot,
				entity,
				source_plot.building.damage
			)


func _apply_damage(
	owner: Entity,
	source_plot: Plot,
	target: Entity,
	requested_damage: int
) -> int:
	if requested_damage <= 0 or target.is_defeated():
		return 0
	var resolved_damage := requested_damage
	if is_instance_valid(_set_bonus_system):
		resolved_damage = _set_bonus_system.modify_outgoing_damage(
			owner,
			resolved_damage
		)
		resolved_damage = _set_bonus_system.modify_incoming_damage(
			target,
			resolved_damage
		)
	var dealt_damage := target.take_damage(resolved_damage)
	if dealt_damage > 0:
		activation_resolved.emit(BuildingActivation.new(
			BuildingActivation.EffectKind.DAMAGE,
			owner,
			source_plot,
			source_plot.building,
			target,
			dealt_damage
		))
	return dealt_damage


func _get_connected_tesla_count(start_plot: Plot, owner: Entity) -> int:
	var tesla_plots: Array[Plot] = []
	for plot in _board.plots:
		if (
			plot.plot_owner == owner
			and plot.has_building_type(BuildingData.BuildingType.TESLA_COIL)
		):
			tesla_plots.append(plot)
	if not tesla_plots.has(start_plot):
		return 0

	var connected_count := 0
	var queue: Array[Plot] = [start_plot]
	var visited: Dictionary[int, bool] = {}
	while not queue.is_empty():
		var current: Plot = queue.pop_front() as Plot
		var current_id := current.get_instance_id()
		if visited.has(current_id):
			continue
		visited[current_id] = true
		connected_count += 1
		for candidate in tesla_plots:
			if visited.has(candidate.get_instance_id()):
				continue
			var connection_range := mini(
				current.building.range_spaces,
				candidate.building.range_spaces
			)
			if _board.get_route_distance(current, candidate) <= connection_range:
				queue.append(candidate)
	return connected_count
