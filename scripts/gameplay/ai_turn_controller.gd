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
	var dice_values := game_manager.get_upcoming_roll(expected_entity)
	if dice_values.is_empty():
		dice_values = expected_entity.roll_dice()
	var adjustment := _choose_guided_current_adjustment(
		game_manager,
		expected_entity,
		dice_values
	)
	await game_manager.play_active_turn(dice_values, adjustment)
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
		if (
			candidate != null
			and entity.money >= game_manager.get_building_cost(entity, candidate)
		):
			return game_manager.request_construct_building(entity, plot, candidate)
	return false


func _choose_guided_current_adjustment(
	game_manager: GameManager,
	entity: Entity,
	dice_values: Array[int]
) -> int:
	if not game_manager.set_bonus_system.can_adjust_movement(entity):
		return 0
	var current_index := game_manager.board.get_entity_plot_index(entity)
	var rolled_total: int = dice_values[0] + dice_values[1]
	var best_adjustment := 0
	var best_score := -INF
	for adjustment in [-1, 0, 1]:
		var destination := game_manager.board.get_plot(
			posmod(
				current_index + rolled_total + adjustment,
				game_manager.board.plots.size()
			)
		)
		var score := _score_destination(entity, destination)
		if score > best_score:
			best_score = score
			best_adjustment = adjustment
	return best_adjustment


func _score_destination(entity: Entity, plot: Plot) -> float:
	if not is_instance_valid(plot) or plot.data == null:
		return -1000.0
	if plot.data.type == PlotData.PlotType.CARD:
		return 2.0
	if plot.plot_owner == entity:
		return 1.5
	if not is_instance_valid(plot.plot_owner) and plot.data.is_ownable():
		return 3.0 if entity.money >= plot.get_buy_price() else 0.25
	if is_instance_valid(plot.plot_owner) and plot.plot_owner != entity:
		return -float(plot.get_rent_value())
	return 0.0


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
