class_name AiTurnController
extends Node

## Stateless AI policy. It reacts to one turn token and submits the same public
## commands a human/controller would submit through GameManager.
func schedule_turn(
	game_manager: GameManager,
	expected_entity: Entity,
	turn_token: int,
	delay_seconds: float
) -> void:
	await get_tree().create_timer(delay_seconds).timeout
	if not _is_current_turn(game_manager, expected_entity, turn_token):
		return
	if game_manager.is_turn_resolving() or expected_entity.is_defeated():
		return
	await game_manager.play_active_turn(expected_entity.roll_dice())
	if not _is_current_turn(game_manager, expected_entity, turn_token):
		return

	var pending_rent := game_manager.get_pending_rent_plot()
	if is_instance_valid(pending_rent):
		game_manager.request_rent_payment(expected_entity)
	var pending_purchase := game_manager.get_pending_purchase_plot()
	if is_instance_valid(pending_purchase):
		var purchased := game_manager.request_property_purchase(
			expected_entity,
			expected_entity.money >= pending_purchase.get_buy_price()
		)
		if purchased:
			_try_construct_building(game_manager, expected_entity, pending_purchase)
	game_manager.request_end_turn(expected_entity)


func _try_construct_building(
	game_manager: GameManager,
	entity: Entity,
	plot: Plot
) -> bool:
	if game_manager.available_buildings.is_empty() or not is_instance_valid(plot):
		return false
	var plot_index := game_manager.board.plots.find(plot)
	for offset in game_manager.available_buildings.size():
		var candidate := game_manager.available_buildings[
			posmod(plot_index + offset, game_manager.available_buildings.size())
		]
		if candidate != null and entity.money >= candidate.build_cost:
			return game_manager.request_construct_building(entity, plot, candidate)
	return false


func _is_current_turn(
	game_manager: GameManager,
	expected_entity: Entity,
	turn_token: int
) -> bool:
	return (
		game_manager.state == GameManager.MatchState.ACTIVE
		and game_manager.get_turn_token() == turn_token
		and game_manager.get_active_entity() == expected_entity
	)
