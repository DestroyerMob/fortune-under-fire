class_name CardEffectSystem
extends Node

## Resolves board-specific card facts and movement. Match phase validation,
## card consumption, roll allowances, and turn advancement remain in the
## GameManager command facade.


func has_hospital(board: Board, entity: Entity) -> bool:
	return get_forward_hospital_distance(board, entity) > 0


func get_forward_hospital_distance(board: Board, entity: Entity) -> int:
	if not is_instance_valid(board) or not is_instance_valid(entity):
		return -1
	if board.plots.is_empty():
		return -1
	var current_index := board.get_entity_plot_index(entity)
	if current_index < 0:
		return -1

	# Search strictly ahead. If the only hospital is the current plot, travelling
	# a full lap back to it is intentional and can award Start income.
	for distance in range(1, board.plots.size() + 1):
		var candidate := board.get_plot(
			posmod(current_index + distance, board.plots.size())
		)
		if (
			is_instance_valid(candidate)
			and candidate.has_building_type(
				BuildingData.BuildingType.MEDIC_TOWER
			)
		):
			return distance
	return -1


func move_to_nearest_hospital(board: Board, entity: Entity) -> int:
	var distance := get_forward_hospital_distance(board, entity)
	if distance <= 0:
		return -1
	return await board.move_entity_by_spaces(entity, distance)
