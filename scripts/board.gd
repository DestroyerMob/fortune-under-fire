class_name Board
extends Node3D

## Emitted once each time an entity crosses from the final plot back to Start,
## after its owned-property income has been awarded.
signal past_start(entity: Entity)
signal start_income_awarded(entity: Entity, amount: int)
signal movement_started(entity: Entity, spaces: int, destination_index: int)
## Emitted after reaching an intermediate plot. Pass effects such as traps can
## react here and call stop_entity_movement(entity).
signal plot_passed(entity: Entity, plot: Plot, plot_index: int)
## Emitted only after the entity physically reaches its rolled destination.
signal plot_landed(entity: Entity, plot: Plot, plot_index: int)
signal movement_interrupted(entity: Entity, plot_index: int)
signal movement_finished(entity: Entity, destination_index: int)
signal building_activated(
	owner: Entity,
	source_plot: Plot,
	building: BuildingData,
	target: Entity,
	money_amount: int,
	damage_amount: int,
	healing_amount: int,
	die_roll: int
)
signal building_effect_resolved(activation: BuildingActivation)

@export_category("Movement")
@export_range(0.1, 20.0, 0.1, "suffix:m/s") var movement_units_per_second := 5.0
## The normal spacing between edge plots, used to scale speed for unusual gaps.
@export_range(0.1, 10.0, 0.1, "suffix:m") var reference_plot_distance := 1.5
## At 0 all steps use the same speed. Values above 0 make entities travel faster
## across longer gaps while still taking longer than a normal-sized step.
@export_range(0.0, 0.9, 0.05) var distance_speed_exponent := 0.5

# Each side's children are already ordered from the preceding corner to the
# following corner. Starting at SouthEast matches the player's starting space.
const SIDE_NAMES: Array[StringName] = [&"South", &"West", &"North", &"East"]
const CORNER_NAMES: Array[StringName] = [
	&"SouthEast",
	&"SouthWest",
	&"NorthWest",
	&"NorthEast",
]

var plots: Array[Plot] = []
var _entity_plot_indices: Dictionary[int, int] = {}
var _moving_entity_ids: Dictionary[int, bool] = {}
var _movement_stop_requests: Dictionary[int, bool] = {}
var building_effect_system: BuildingEffectSystem

func _ready() -> void:
	plots = _collect_plots()
	building_effect_system = get_node_or_null(^"BuildingEffectSystem") as BuildingEffectSystem
	if building_effect_system == null:
		building_effect_system = BuildingEffectSystem.new()
		building_effect_system.name = "BuildingEffectSystem"
		add_child(building_effect_system)
	building_effect_system.configure(self)
	building_effect_system.activation_resolved.connect(_on_building_effect_resolved)

	if plots.is_empty():
		push_error("Board has no plots in its movement route.")


## Adds an entity to this board and places it at a wrapped plot index.
func register_entity(entity: Entity, starting_index := 0) -> int:
	if not _can_move_entity(entity):
		return -1

	var wrapped_index := posmod(starting_index, plots.size())
	_entity_plot_indices[entity.get_instance_id()] = wrapped_index
	entity.global_position = _get_entity_plot_position(entity, wrapped_index)
	return wrapped_index


## Sums two six-sided dice, then visits each plot in sequence. Await this method
## when subsequent turn logic must wait until movement and landing are complete.
## Returns the destination index, or -1 when the request is invalid.
func move_entity(entity: Entity, dice_values: Array[int]) -> int:
	if not _can_move_entity(entity):
		return -1
	if is_entity_moving(entity):
		return get_entity_plot_index(entity)

	if dice_values.size() != 2:
		push_error("Board movement requires exactly two dice values.")
		return -1

	var spaces_to_move := 0
	for die_value in dice_values:
		if die_value < 1 or die_value > 6:
			push_error("Dice values must be between 1 and 6.")
			return -1
		spaces_to_move += die_value

	return await move_entity_by_spaces(entity, spaces_to_move)


## Moves forward through the normal route without fabricating dice. Card and
## future forced-movement effects use this so passing Start, pass triggers,
## landing behavior, and presentation remain identical to a rolled move.
func move_entity_by_spaces(entity: Entity, spaces_to_move: int) -> int:
	if not _can_move_entity(entity) or spaces_to_move <= 0:
		return -1
	if is_entity_moving(entity):
		return get_entity_plot_index(entity)
	return await _move_entity_by_spaces(entity, spaces_to_move)


func get_entity_plot_index(entity: Entity) -> int:
	if not is_instance_valid(entity):
		return -1
	return _entity_plot_indices.get(entity.get_instance_id(), -1)


func is_entity_moving(entity: Entity) -> bool:
	if not is_instance_valid(entity):
		return false
	return _moving_entity_ids.has(entity.get_instance_id())


func is_any_entity_moving() -> bool:
	return not _moving_entity_ids.is_empty()


func get_plot(plot_index: int) -> Plot:
	if plot_index < 0 or plot_index >= plots.size():
		return null
	return plots[plot_index]


func reset_plot_ownership() -> void:
	for plot in plots:
		plot.reset_ownership()
		plot.clear_building()


func get_owned_property_income(entity: Entity) -> int:
	if not is_instance_valid(entity):
		return 0

	var income := 0
	for plot in plots:
		if (
			plot.plot_owner == entity
			and plot.data != null
			and plot.data.is_ownable()
		):
			income += plot.get_base_rent()
	return income


func get_owned_properties(entity: Entity) -> Array[Plot]:
	var owned_properties: Array[Plot] = []
	if not is_instance_valid(entity):
		return owned_properties

	for plot in plots:
		if (
			plot.plot_owner == entity
			and plot.data != null
			and plot.data.is_ownable()
		):
			owned_properties.append(plot)
	return owned_properties


func award_start_income(entity: Entity) -> int:
	var income := get_owned_property_income(entity)
	income += building_effect_system.activate_lap(
		entity,
		get_owned_properties(entity)
	)
	if income > 0:
		entity.add_money(income)
	start_income_awarded.emit(entity, income)
	return income


## Safely interrupts movement after the entity reaches its current step. This is
## intended for pass effects such as trap cards; no landing behaviour is run.
func stop_entity_movement(entity: Entity) -> void:
	if is_entity_moving(entity):
		_movement_stop_requests[entity.get_instance_id()] = true


## Returns the direction pointing from the board interior through a plot. Edge
## plots share one cardinal direction; corner plots use their 45-degree diagonal.
func get_plot_outward_direction(plot_index: int) -> Vector3:
	if plots.is_empty():
		return Vector3.ZERO

	var plot := plots[posmod(plot_index, plots.size())]
	var segment := plot.get_parent() as Node3D
	var direction_source: Node3D = plot if segment.name == &"Corners" else segment
	var outward_direction := direction_source.global_position - global_position
	outward_direction.y = 0.0
	return outward_direction.normalized()


func get_entity_outward_direction(entity: Entity) -> Vector3:
	var plot_index := get_entity_plot_index(entity)
	if plot_index == -1:
		return Vector3.ZERO
	return get_plot_outward_direction(plot_index)


func get_route_distance(first_plot: Plot, second_plot: Plot) -> int:
	var first_index := plots.find(first_plot)
	var second_index := plots.find(second_plot)
	if first_index == -1 or second_index == -1 or plots.is_empty():
		return -1
	var direct_distance := absi(first_index - second_index)
	return mini(direct_distance, plots.size() - direct_distance)


func _move_entity_by_spaces(entity: Entity, spaces_to_move: int) -> int:
	var current_index := get_entity_plot_index(entity)
	if current_index == -1:
		current_index = register_entity(entity)
		if current_index == -1:
			return -1

	var entity_id := entity.get_instance_id()
	var destination_index := posmod(current_index + spaces_to_move, plots.size())
	_moving_entity_ids[entity_id] = true
	_movement_stop_requests.erase(entity_id)
	movement_started.emit(entity, spaces_to_move, destination_index)

	for _step in spaces_to_move:
		var next_index := posmod(current_index + 1, plots.size())

		# Publish the next segment before moving so the camera can begin its smooth
		# 45-degree corner transition while the entity approaches that plot.
		_entity_plot_indices[entity_id] = next_index
		var next_position := _get_entity_plot_position(entity, next_index)
		var step_distance := entity.global_position.distance_to(next_position)
		var movement_tween := create_tween().bind_node(entity)
		movement_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		movement_tween.tween_property(
			entity,
			^"global_position",
			next_position,
			_get_step_duration(step_distance)
		)
		await movement_tween.finished

		if not is_instance_valid(entity):
			_moving_entity_ids.erase(entity_id)
			return -1

		current_index = next_index
		if current_index == 0:
			award_start_income(entity)
			past_start.emit(entity)

		var reached_destination := current_index == destination_index
		if not reached_destination:
			plot_passed.emit(entity, plots[current_index], current_index)
			if _movement_stop_requests.has(entity_id):
				_movement_stop_requests.erase(entity_id)
				_moving_entity_ids.erase(entity_id)
				movement_interrupted.emit(entity, current_index)
				return current_index

	_movement_stop_requests.erase(entity_id)
	_moving_entity_ids.erase(entity_id)
	# Landing behaviour is deliberately deferred until the destination tween has
	# completed. Intermediate plots only emit plot_passed above.
	plots[destination_index].on_land(entity)
	building_effect_system.activate_landing(entity, plots[destination_index])
	plot_landed.emit(entity, plots[destination_index], destination_index)
	movement_finished.emit(entity, destination_index)
	return destination_index


func _on_building_effect_resolved(activation: BuildingActivation) -> void:
	building_effect_resolved.emit(activation)
	# Compatibility bridge for presentation/tests that still consume the former
	# positional event. New systems should prefer building_effect_resolved.
	building_activated.emit(
		activation.owner,
		activation.source_plot,
		activation.building,
		activation.target,
		activation.get_money_amount(),
		activation.get_damage_amount(),
		activation.get_healing_amount(),
		activation.die_roll
	)


func _get_step_duration(step_distance: float) -> float:
	var distance_ratio := maxf(step_distance / reference_plot_distance, 0.001)
	var adaptive_speed := movement_units_per_second * pow(
		distance_ratio,
		distance_speed_exponent
	)
	return step_distance / maxf(adaptive_speed, 0.001)


func _get_entity_plot_position(entity: Entity, plot_index: int) -> Vector3:
	return (
		plots[plot_index].global_position
		+ Vector3.UP * entity.plot_vertical_offset
	)


func _can_move_entity(entity: Entity) -> bool:
	if not is_instance_valid(entity):
		push_error("Cannot move an invalid entity.")
		return false

	if plots.is_empty():
		push_error("Cannot move an entity before the board route is ready.")
		return false

	return true


func _collect_plots() -> Array[Plot]:
	var ordered_plots: Array[Plot] = []

	for index in SIDE_NAMES.size():
		var corner := get_node("Corners/%s" % CORNER_NAMES[index]) as Plot
		ordered_plots.append(corner)

		var side := get_node(NodePath(SIDE_NAMES[index]))
		for child in side.get_children():
			if child is Plot:
				ordered_plots.append(child)

	return ordered_plots
