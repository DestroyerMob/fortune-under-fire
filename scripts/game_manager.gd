class_name GameManager
extends Node

const CARD_PLAY_RESULT_SCRIPT := preload("res://scripts/gameplay/card_play_result.gd")
const CARD_EFFECT_SYSTEM_SCRIPT := preload("res://scripts/gameplay/card_effect_system.gd")

signal match_started(participants: Array[Entity])
signal match_finished(winner: Entity)
signal participant_eliminated(entity: Entity, reason: int)
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
signal property_purchase_offered(
	entity: Entity,
	plot: Plot,
	buy_price: int,
	base_rent: int,
	tower_rent: int
)
signal property_purchase_resolved(entity: Entity, plot: Plot, purchased: bool, price: int)
signal rent_payment_required(payer: Entity, owner: Entity, plot: Plot, amount: int)
signal rent_paid(payer: Entity, owner: Entity, plot: Plot, amount: int)
signal start_income_awarded(entity: Entity, amount: int)
signal card_play_started(entity: Entity, card: CardData)
signal card_played(result)
signal debug_card_granted(entity: Entity, card: CardData)
signal building_constructed(owner: Entity, plot: Plot, building: BuildingData, cost: int)
signal building_activated(
	owner: Entity,
	plot: Plot,
	building: BuildingData,
	target: Entity,
	money_amount: int,
	damage_amount: int,
	healing_amount: int,
	die_roll: int
)
signal building_effect_resolved(activation: BuildingActivation)
signal bank_transaction_completed(
	entity: Entity,
	plot: Plot,
	kind: StringName,
	amount: int,
	new_balance: int
)
signal bank_interest_credited(owner: Entity, plot: Plot, amount: int, new_balance: int)
signal complete_sets_changed(
	entity: Entity,
	controlled_sets: Array[PropertyGroupData]
)
signal set_bonus_charge_changed(
	entity: Entity,
	group: PropertyGroupData,
	charges: int
)
signal set_bonus_triggered(
	entity: Entity,
	group: PropertyGroupData,
	amount: int,
	context: StringName
)
signal upcoming_roll_revealed(entity: Entity, dice_values: Array[int])
signal movement_adjustment_required(
	entity: Entity,
	dice_values: Array[int],
	maximum_adjustment: int
)
signal movement_adjustment_resolved(entity: Entity, adjustment: int, movement_total: int)

enum MatchState {LOBBY, ACTIVE, FINISHED}

const MAX_PARTICIPANTS := 4

@export_category("Match")
@export var board: Board
## Ordered turn list. Invalid and duplicate entries are removed at match start.
@export var participants: Array[Entity] = []
@export var available_buildings: Array[BuildingData] = []
@export var debug_card_selector: CardSelector
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
var _rolls_remaining := 0
var _last_destination_index := -1
var _turn_generation := 0
var _prepared_dice_values: Array[int] = []
var _pending_movement_dice: Array[int] = []
var _hospital_run_round_by_entity: Dictionary[Entity, int] = {}
var property_action_system: PropertyActionSystem
var ai_turn_controller: AiTurnController
var card_effect_system
var set_bonus_system: SetBonusSystem


func _ready() -> void:
	_ensure_gameplay_systems()
	if auto_start:
		call_deferred(&"start_match")


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

	_ensure_gameplay_systems()
	if not board.start_income_awarded.is_connected(_on_start_income_awarded):
		board.start_income_awarded.connect(_on_start_income_awarded)
	if not board.building_effect_resolved.is_connected(_on_board_building_effect_resolved):
		board.building_effect_resolved.connect(_on_board_building_effect_resolved)
	property_action_system.clear_pending_action()
	_hospital_run_round_by_entity.clear()
	board.reset_plot_ownership()
	for participant in participants:
		if reset_entities_on_start:
			participant.reset_for_match()
		if not participant.defeated.is_connected(_on_participant_defeated):
			participant.defeated.connect(_on_participant_defeated)
		board.register_entity(participant, starting_plot_index)
	set_bonus_system.reset_for_match(participants)

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


func has_roll_available() -> bool:
	return _rolls_remaining > 0


func has_pending_movement_adjustment() -> bool:
	return not _pending_movement_dice.is_empty()


func get_upcoming_roll(entity: Entity) -> Array[int]:
	if entity != get_active_entity():
		return []
	return _prepared_dice_values.duplicate()


func get_complete_property_sets(entity: Entity) -> Array[PropertyGroupData]:
	return set_bonus_system.get_complete_sets(entity)


func get_building_cost(entity: Entity, building: BuildingData) -> int:
	if building == null:
		return 0
	return set_bonus_system.get_construction_cost(entity, building.build_cost)


func get_pending_purchase_plot() -> Plot:
	return property_action_system.get_pending_purchase_plot()


func has_pending_purchase() -> bool:
	return is_instance_valid(get_pending_purchase_plot())


func get_pending_rent_plot() -> Plot:
	return property_action_system.get_pending_rent_plot()


func has_pending_rent() -> bool:
	return is_instance_valid(get_pending_rent_plot())


func get_pending_landing_action_plot() -> Plot:
	return property_action_system.get_pending_plot()


func has_pending_landing_action() -> bool:
	return property_action_system.has_pending_action()


func get_turn_token() -> int:
	return _turn_generation


## Shared action behind both the turn button and its keyboard shortcut. Before
## rolling it rolls; after movement resolves it ends the turn.
func request_turn_action(requesting_entity: Entity = null) -> bool:
	if has_pending_movement_adjustment():
		return false
	if has_roll_available():
		return request_roll(requesting_entity)
	if has_active_entity_rolled():
		return request_end_turn(requesting_entity)
	return false


## Multiplayer authority can instead call play_active_turn() with validated
## dice values and replicate the result.
func request_roll(requesting_entity: Entity = null) -> bool:
	var active_entity := get_active_entity()
	if not _can_resolve_turn(active_entity):
		return false
	if requesting_entity != null and requesting_entity != active_entity:
		return false
	if active_entity.type == Entity.EntityType.AI and auto_play_ai:
		return false

	var dice_values := (
		_prepared_dice_values.duplicate()
		if not _prepared_dice_values.is_empty()
		else active_entity.roll_dice()
	)
	_prepared_dice_values.clear()
	if set_bonus_system.can_adjust_movement(active_entity):
		_begin_roll(active_entity, dice_values)
		_pending_movement_dice = dice_values.duplicate()
		var group := set_bonus_system.get_controlled_group(
			active_entity,
			PropertyGroupData.ControlBonus.GUIDED_CURRENT
		)
		movement_adjustment_required.emit(
			active_entity,
			dice_values.duplicate(),
			group.control_bonus_value
		)
		return true
	play_active_turn(dice_values)
	return true


func request_movement_adjustment(
	requesting_entity: Entity,
	adjustment: int
) -> bool:
	var active_entity := get_active_entity()
	if (
		state != MatchState.ACTIVE
		or _turn_is_resolving
		or requesting_entity != active_entity
		or not has_pending_movement_adjustment()
		or not set_bonus_system.consume_movement_adjustment(active_entity, adjustment)
	):
		return false
	var dice_values := _pending_movement_dice.duplicate()
	_pending_movement_dice.clear()
	var movement_total: int = dice_values[0] + dice_values[1] + adjustment
	movement_adjustment_resolved.emit(active_entity, adjustment, movement_total)
	_resolve_roll_movement(active_entity, dice_values, movement_total)
	return true


## Resolves the active participant's roll. The turn remains active after physical
## movement and landing behaviour complete until request_end_turn() is called.
func play_active_turn(dice_values: Array[int], movement_adjustment := 0) -> int:
	var active_entity := get_active_entity()
	if not _can_resolve_turn(active_entity):
		return -1
	if not _are_valid_dice(dice_values):
		push_error("A turn requires exactly two dice values between 1 and 6.")
		return -1
	if (
		movement_adjustment != 0
		and not set_bonus_system.consume_movement_adjustment(
			active_entity,
			movement_adjustment
		)
	):
		return -1

	_prepared_dice_values.clear()
	_begin_roll(active_entity, dice_values)
	return await _resolve_roll_movement(
		active_entity,
		dice_values,
		dice_values[0] + dice_values[1] + movement_adjustment
	)


func _begin_roll(active_entity: Entity, dice_values: Array[int]) -> void:
	_rolls_remaining -= 1
	_active_entity_has_rolled = true
	dice_rolled.emit(active_entity, dice_values.duplicate())


func _resolve_roll_movement(
	active_entity: Entity,
	dice_values: Array[int],
	movement_total: int
) -> int:
	_turn_is_resolving = true
	var resolving_index := active_participant_index
	var resolving_round := round_number
	var resolving_turn := turn_number
	var rolled_values := dice_values.duplicate()
	var unmodified_total: int = rolled_values[0] + rolled_values[1]
	var destination_index: int
	if movement_total == unmodified_total:
		destination_index = await board.move_entity(active_entity, rolled_values)
	else:
		destination_index = await board.move_entity_by_spaces(
			active_entity,
			movement_total
		)
	_turn_is_resolving = false
	_last_destination_index = destination_index
	roll_finished.emit(
		active_entity,
		destination_index,
		resolving_index,
		resolving_round,
		resolving_turn
	)
	# Damage buildings can defeat the moving entity on its destination. The
	# defeated signal fires while movement is resolving, so settle that outcome
	# here once the board and camera have completed the roll.
	if active_entity.is_defeated() and get_active_entity() == active_entity:
		property_action_system.clear_pending_action()
		turn_skipped.emit(active_entity, _get_defeat_reason_id(active_entity))
		_advance_turn()

	return destination_index


## Ends a turn after its roll and movement have resolved. Human UI, AI logic,
## and future network authority all use the same validation path.
func request_end_turn(requesting_entity: Entity = null) -> bool:
	var active_entity := get_active_entity()
	if (
		state != MatchState.ACTIVE
		or _turn_is_resolving
		or has_pending_movement_adjustment()
	):
		return false
	if not is_instance_valid(active_entity) or not _active_entity_has_rolled:
		return false
	if requesting_entity != null and requesting_entity != active_entity:
		return false

	# Ending the turn is the convenient fallback for plot interactions: an
	# unanswered purchase is declined and mandatory rent is settled first.
	if has_pending_rent() and not request_rent_payment(active_entity):
		return false
	if active_entity.is_defeated():
		property_action_system.clear_pending_action()
		turn_skipped.emit(active_entity, _get_defeat_reason_id(active_entity))
		_advance_turn()
		return true
	if has_pending_purchase():
		request_property_purchase(active_entity, false)
	if has_pending_landing_action():
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


## Accepts or declines the active entity's pending property offer. A failed
## purchase leaves the offer open so the player can still decline it.
func request_property_purchase(
	requesting_entity: Entity,
	should_purchase: bool
) -> bool:
	var active_entity := get_active_entity()
	var pending_plot := get_pending_purchase_plot()
	if (
		state != MatchState.ACTIVE
		or _turn_is_resolving
		or not _active_entity_has_rolled
		or not is_instance_valid(active_entity)
		or requesting_entity != active_entity
		or not is_instance_valid(pending_plot)
	):
		return false
	return property_action_system.resolve_purchase(active_entity, should_purchase)


func request_rent_payment(requesting_entity: Entity) -> bool:
	var active_entity := get_active_entity()
	var pending_plot := get_pending_rent_plot()
	if (
		state != MatchState.ACTIVE
		or _turn_is_resolving
		or not _active_entity_has_rolled
		or not is_instance_valid(active_entity)
		or requesting_entity != active_entity
		or not is_instance_valid(pending_plot)
	):
		return false
	return property_action_system.pay_rent(active_entity)


func request_construct_building(
	requesting_entity: Entity,
	plot: Plot,
	building: BuildingData
) -> bool:
	var active_entity := get_active_entity()
	var construction_cost := get_building_cost(active_entity, building)
	if (
		state != MatchState.ACTIVE
		or _turn_is_resolving
		or not is_instance_valid(active_entity)
		or requesting_entity != active_entity
		or not is_instance_valid(plot)
		or building == null
		or has_pending_movement_adjustment()
		or has_pending_landing_action()
		or not available_buildings.has(building)
		or not plot.can_construct_building(active_entity, building, construction_cost)
	):
		return false

	if not plot.construct_building(active_entity, building, construction_cost):
		return false
	set_bonus_system.commit_construction_discount(
		active_entity,
		building.build_cost,
		construction_cost
	)
	building_constructed.emit(active_entity, plot, building, construction_cost)
	return true


func request_bank_deposit(
	requesting_entity: Entity,
	plot: Plot,
	amount: int
) -> bool:
	if not _can_manage_bank(requesting_entity, plot) or amount > requesting_entity.money:
		return false
	if not plot.deposit_to_bank(requesting_entity, amount):
		return false
	bank_transaction_completed.emit(
		requesting_entity,
		plot,
		&"deposit",
		amount,
		plot.get_bank_balance()
	)
	return true


func request_bank_withdrawal(
	requesting_entity: Entity,
	plot: Plot,
	amount: int
) -> bool:
	if not _can_manage_bank(requesting_entity, plot) or amount > plot.get_bank_balance():
		return false
	if not plot.withdraw_from_bank(requesting_entity, amount):
		return false
	bank_transaction_completed.emit(
		requesting_entity,
		plot,
		&"withdrawal",
		amount,
		plot.get_bank_balance()
	)
	return true


func _can_manage_bank(requesting_entity: Entity, plot: Plot) -> bool:
	return (
		state == MatchState.ACTIVE
		and not _turn_is_resolving
		and not has_pending_movement_adjustment()
		and not has_pending_landing_action()
		and is_instance_valid(requesting_entity)
		and requesting_entity == get_active_entity()
		and not requesting_entity.is_defeated()
		and is_instance_valid(plot)
		and plot.can_manage_bank(requesting_entity)
	)


func can_play_card(requesting_entity: Entity, card: CardData) -> bool:
	var active_entity := get_active_entity()
	if (
		state != MatchState.ACTIVE
		or _turn_is_resolving
		or has_pending_movement_adjustment()
		or not is_instance_valid(active_entity)
		or requesting_entity != active_entity
		or card == null
		or requesting_entity.get_card_quantity(card) <= 0
		or has_pending_landing_action()
	):
		return false

	match card.effect:
		CardData.EffectType.END_TURN_WITHOUT_ROLL:
			return not _active_entity_has_rolled
		CardData.EffectType.ADDITIONAL_ROLL:
			return _active_entity_has_rolled and not has_roll_available()
		CardData.EffectType.MOVE_TO_NEAREST_HOSPITAL:
			return (
				int(_hospital_run_round_by_entity.get(active_entity, -1))
				!= round_number
				and card_effect_system.has_hospital(board, active_entity)
			)
	return false


## Developer-only mutation surface. Presentation gates access behind the local
## Dev Tools setting; authority still restricts the grant to the active human.
func debug_grant_random_card(requesting_entity: Entity) -> CardData:
	if (
		state != MatchState.ACTIVE
		or requesting_entity != get_active_entity()
		or not is_instance_valid(requesting_entity)
		or requesting_entity.type != Entity.EntityType.PLAYER
		or requesting_entity.is_defeated()
		or debug_card_selector == null
	):
		return null
	var card := debug_card_selector.draw_card()
	if card == null or not requesting_entity.add_card(card):
		return null
	debug_card_granted.emit(requesting_entity, card)
	return card


func can_target_card(
	requesting_entity: Entity,
	card: CardData,
	target_plot: Plot = null
) -> bool:
	if not can_play_card(requesting_entity, card):
		return false
	match card.target_mode:
		CardData.TargetMode.SELF:
			return target_plot == null
		CardData.TargetMode.PROPERTY:
			return (
				is_instance_valid(target_plot)
				and board.plots.has(target_plot)
				and target_plot.data != null
				and target_plot.data.is_ownable()
			)
	return false


## Plays one card through the authoritative turn facade. Callers should await
## this command because movement cards complete only after their route travel
## and landing effects have resolved.
func request_play_card(
	requesting_entity: Entity,
	card: CardData,
	target_plot: Plot = null
) -> bool:
	if not can_target_card(requesting_entity, card, target_plot):
		return false
	if not requesting_entity.remove_card(card):
		return false

	if card.effect == CardData.EffectType.MOVE_TO_NEAREST_HOSPITAL:
		_turn_is_resolving = true
	card_play_started.emit(requesting_entity, card)
	match card.effect:
		CardData.EffectType.END_TURN_WITHOUT_ROLL:
			card_played.emit(CARD_PLAY_RESULT_SCRIPT.new(
				requesting_entity,
				card,
				CARD_PLAY_RESULT_SCRIPT.Outcome.TURN_ENDED,
				board.get_entity_plot_index(requesting_entity)
			))
			turn_finished.emit(
				requesting_entity,
				board.get_entity_plot_index(requesting_entity),
				active_participant_index,
				round_number,
				turn_number
			)
			_advance_turn()
			return true
		CardData.EffectType.ADDITIONAL_ROLL:
			_rolls_remaining += 1
			card_played.emit(CARD_PLAY_RESULT_SCRIPT.new(
				requesting_entity,
				card,
				CARD_PLAY_RESULT_SCRIPT.Outcome.ADDITIONAL_ROLL_GRANTED,
				board.get_entity_plot_index(requesting_entity)
			))
			_prepare_upcoming_roll(requesting_entity)
			return true
		CardData.EffectType.MOVE_TO_NEAREST_HOSPITAL:
			var destination_index: int = await card_effect_system.move_to_nearest_hospital(
				board,
				requesting_entity
			)
			_turn_is_resolving = false
			if destination_index < 0:
				requesting_entity.add_card(card)
				return false
			_hospital_run_round_by_entity[requesting_entity] = round_number
			_last_destination_index = destination_index
			card_played.emit(CARD_PLAY_RESULT_SCRIPT.new(
				requesting_entity,
				card,
				CARD_PLAY_RESULT_SCRIPT.Outcome.MOVED_TO_HOSPITAL,
				destination_index
			))
			return true

	requesting_entity.add_card(card)
	return false


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
	_rolls_remaining = 1
	_last_destination_index = -1
	_pending_movement_dice.clear()
	_prepared_dice_values.clear()
	property_action_system.clear_pending_action()
	set_bonus_system.begin_turn(active_entity)
	turn_started.emit(
		active_entity,
		active_participant_index,
		round_number,
		turn_number
	)
	_prepare_upcoming_roll(active_entity)

	if active_entity.type == Entity.EntityType.AI and auto_play_ai:
		ai_turn_controller.schedule_turn(
			self,
			active_entity,
			_turn_generation,
			ai_roll_delay
		)


func _prepare_upcoming_roll(entity: Entity) -> void:
	_prepared_dice_values.clear()
	if not set_bonus_system.controls_bonus(
		entity,
		PropertyGroupData.ControlBonus.INTELLIGENCE_NETWORK
	):
		return
	_prepared_dice_values = entity.roll_dice()
	upcoming_roll_revealed.emit(entity, _prepared_dice_values.duplicate())


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
	_rolls_remaining = 0
	_last_destination_index = -1
	_prepared_dice_values.clear()
	_pending_movement_dice.clear()
	property_action_system.clear_pending_action()
	_turn_generation += 1
	active_participant_index = -1
	match_finished.emit(winner)


func _ensure_gameplay_systems() -> void:
	property_action_system = get_node_or_null(^"PropertyActionSystem") as PropertyActionSystem
	if property_action_system == null:
		property_action_system = PropertyActionSystem.new()
		property_action_system.name = "PropertyActionSystem"
		add_child(property_action_system)
	ai_turn_controller = get_node_or_null(^"AiTurnController") as AiTurnController
	if ai_turn_controller == null:
		ai_turn_controller = AiTurnController.new()
		ai_turn_controller.name = "AiTurnController"
		add_child(ai_turn_controller)
	card_effect_system = get_node_or_null(^"CardEffectSystem")
	if card_effect_system == null:
		card_effect_system = CARD_EFFECT_SYSTEM_SCRIPT.new()
		card_effect_system.name = "CardEffectSystem"
		add_child(card_effect_system)
	set_bonus_system = get_node_or_null(^"SetBonusSystem") as SetBonusSystem
	if set_bonus_system == null:
		set_bonus_system = SetBonusSystem.new()
		set_bonus_system.name = "SetBonusSystem"
		add_child(set_bonus_system)

	if is_instance_valid(board):
		property_action_system.configure(board, _can_offer_property_action)
		set_bonus_system.configure(board, participants)
		board.building_effect_system.set_set_bonus_system(set_bonus_system)
	if not property_action_system.purchase_offered.is_connected(
		_on_property_purchase_offered
	):
		property_action_system.purchase_offered.connect(_on_property_purchase_offered)
		property_action_system.purchase_resolved.connect(_on_property_purchase_resolved)
		property_action_system.rent_required.connect(_on_property_rent_required)
		property_action_system.rent_paid.connect(_on_property_rent_paid)
	if not set_bonus_system.complete_sets_changed.is_connected(
		_on_complete_sets_changed
	):
		set_bonus_system.complete_sets_changed.connect(_on_complete_sets_changed)
		set_bonus_system.charge_changed.connect(_on_set_bonus_charge_changed)
		set_bonus_system.bonus_triggered.connect(_on_set_bonus_triggered)


func _can_offer_property_action(entity: Entity) -> bool:
	return (
		state == MatchState.ACTIVE
		and entity == get_active_entity()
		and _active_entity_has_rolled
		and not has_pending_landing_action()
	)


func _on_property_purchase_offered(
	entity: Entity,
	plot: Plot,
	buy_price: int,
	base_rent: int,
	tower_rent: int
) -> void:
	property_purchase_offered.emit(entity, plot, buy_price, base_rent, tower_rent)


func _on_property_purchase_resolved(
	entity: Entity,
	plot: Plot,
	purchased: bool,
	price: int
) -> void:
	property_purchase_resolved.emit(entity, plot, purchased, price)


func _on_property_rent_required(
	payer: Entity,
	owner: Entity,
	plot: Plot,
	amount: int
) -> void:
	rent_payment_required.emit(payer, owner, plot, amount)


func _on_property_rent_paid(
	payer: Entity,
	owner: Entity,
	plot: Plot,
	amount: int
) -> void:
	rent_paid.emit(payer, owner, plot, amount)
	var tribute := set_bonus_system.consume_tribute(owner, payer, amount)
	if tribute > 0:
		owner.add_money(tribute)
	if amount > 0 and plot.has_building_type(BuildingData.BuildingType.HOTEL):
		_publish_building_effect(BuildingActivation.new(
			BuildingActivation.EffectKind.RENT_INCOME,
			owner,
			plot,
			plot.building,
			payer,
			amount
		))


func _on_start_income_awarded(entity: Entity, amount: int) -> void:
	start_income_awarded.emit(entity, amount)


func _on_complete_sets_changed(
	entity: Entity,
	controlled_sets: Array[PropertyGroupData]
) -> void:
	complete_sets_changed.emit(entity, controlled_sets)


func _on_set_bonus_charge_changed(
	entity: Entity,
	group: PropertyGroupData,
	charges: int
) -> void:
	set_bonus_charge_changed.emit(entity, group, charges)


func _on_set_bonus_triggered(
	entity: Entity,
	group: PropertyGroupData,
	amount: int,
	context: StringName
) -> void:
	set_bonus_triggered.emit(entity, group, amount, context)


func _on_board_building_effect_resolved(activation: BuildingActivation) -> void:
	_publish_building_effect(activation)


func _publish_building_effect(activation: BuildingActivation) -> void:
	building_effect_resolved.emit(activation)
	if activation.kind == BuildingActivation.EffectKind.BANK_INTEREST:
		bank_interest_credited.emit(
			activation.owner,
			activation.source_plot,
			activation.amount,
			activation.source_plot.get_bank_balance()
		)
	# Compatibility bridge; new systems consume the typed event above.
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


func _on_participant_defeated(entity: Entity) -> void:
	if state != MatchState.ACTIVE:
		return
	participant_eliminated.emit(entity, entity.get_defeat_reason())
	if _turn_is_resolving:
		return
	call_deferred(&"_settle_participant_defeat", entity)


func _settle_participant_defeat(entity: Entity) -> void:
	if state != MatchState.ACTIVE or not is_instance_valid(entity):
		return

	var alive := get_alive_participants()
	if alive.size() <= 1:
		_finish_match(alive.front() if not alive.is_empty() else null)
	elif entity == get_active_entity():
		property_action_system.clear_pending_action()
		turn_skipped.emit(entity, _get_defeat_reason_id(entity))
		_advance_turn()


func _get_defeat_reason_id(entity: Entity) -> StringName:
	if not is_instance_valid(entity):
		return &"defeated"
	match entity.get_defeat_reason():
		Entity.DefeatReason.HEALTH:
			return &"health_depleted"
		Entity.DefeatReason.DEBT:
			return &"debt"
	return &"defeated"


func _can_resolve_turn(active_entity: Entity) -> bool:
	return (
		state == MatchState.ACTIVE
		and not _turn_is_resolving
		and not has_pending_movement_adjustment()
		and has_roll_available()
		and not has_pending_landing_action()
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
