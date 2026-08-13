class_name TurnHudController
extends Node

## Owns roll/end-turn input and the compact turn/roll presentation.
var _game_manager: GameManager
var _local_player: Entity
var _turn_label: Label
var _roll_result_label: Label
var _turn_action_button: Button


func configure(
	game_manager: GameManager,
	local_player: Entity,
	turn_label: Label,
	roll_result_label: Label,
	turn_action_button: Button
) -> void:
	_game_manager = game_manager
	_local_player = local_player
	_turn_label = turn_label
	_roll_result_label = roll_result_label
	_turn_action_button = turn_action_button
	_turn_action_button.pressed.connect(perform_turn_action)
	_game_manager.turn_started.connect(_on_turn_started)
	_game_manager.dice_rolled.connect(_on_dice_rolled)
	_game_manager.roll_finished.connect(_on_roll_finished)
	_game_manager.turn_finished.connect(_on_turn_finished)
	_game_manager.property_purchase_offered.connect(_on_purchase_offered)
	_game_manager.property_purchase_resolved.connect(_on_purchase_resolved)
	_game_manager.rent_payment_required.connect(_on_rent_required)
	_game_manager.rent_paid.connect(_on_rent_paid)
	_game_manager.card_play_started.connect(_on_card_play_started)
	_game_manager.card_played.connect(_on_card_played)
	_game_manager.participant_eliminated.connect(_on_participant_eliminated)
	_game_manager.match_finished.connect(_on_match_finished)
	refresh()


func perform_turn_action() -> bool:
	if not _game_manager.request_turn_action(_local_player):
		return false
	refresh()
	return true


func refresh() -> void:
	if not is_instance_valid(_turn_action_button):
		return
	var active_entity := _game_manager.get_active_entity()
	var is_local_turn := active_entity == _local_player
	var is_resolving := _game_manager.is_turn_resolving()
	var has_rolled := _game_manager.has_active_entity_rolled()
	var can_roll := _game_manager.has_roll_available()
	_turn_action_button.visible = (
		_game_manager.state == GameManager.MatchState.ACTIVE
		and is_local_turn
	)
	_turn_action_button.disabled = (
		not is_local_turn
		or is_resolving
		or (can_roll and _game_manager.has_pending_landing_action())
	)
	_turn_action_button.text = (
		"Moving…"
		if is_resolving
		else (
			("Roll Again" if has_rolled else "Roll Dice")
			if can_roll
			else "End Turn"
		)
	)


func _on_turn_started(
	entity: Entity,
	participant_index: int,
	round_number: int,
	_turn_number: int
) -> void:
	var participant_name := _get_participant_name(entity, participant_index)
	_turn_label.text = (
		"Eliminated  ·  Spectating %s" % participant_name
		if _local_player.is_defeated()
		else (
			"Round %d  ·  Your Turn" % round_number
			if entity == _local_player
			else "Round %d  ·  %s" % [round_number, participant_name]
		)
	)
	_roll_result_label.text = ""
	_roll_result_label.hide()
	refresh()


func _on_dice_rolled(entity: Entity, dice_values: Array[int]) -> void:
	var participant_index := _game_manager.participants.find(entity)
	var roll_text := "%d + %d = %d" % [
		dice_values[0], dice_values[1], dice_values[0] + dice_values[1]
	]
	_roll_result_label.text = (
		"Roll  %s" % roll_text
		if entity == _local_player
		else "%s  ·  %s" % [
			_get_participant_name(entity, participant_index),
			roll_text,
		]
	)
	_roll_result_label.show()
	refresh()


func _on_roll_finished(
	_entity: Entity,
	_destination_index: int,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	refresh()


func _on_turn_finished(
	_entity: Entity,
	_destination_index: int,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	refresh()


func _on_purchase_offered(
	_entity: Entity,
	_plot: Plot,
	_buy_price: int,
	_base_rent: int,
	_tower_rent: int
) -> void:
	refresh()


func _on_purchase_resolved(
	_entity: Entity,
	_plot: Plot,
	_purchased: bool,
	_price: int
) -> void:
	refresh()


func _on_rent_required(
	_payer: Entity,
	_owner: Entity,
	_plot: Plot,
	_amount: int
) -> void:
	refresh()


func _on_rent_paid(
	_payer: Entity,
	_owner: Entity,
	_plot: Plot,
	_amount: int
) -> void:
	refresh()


func _on_card_play_started(_entity: Entity, _card: CardData) -> void:
	refresh()


func _on_card_played(_result) -> void:
	refresh()


func _on_participant_eliminated(entity: Entity, _reason: int) -> void:
	if entity != _local_player:
		return
	_turn_label.text = "You are out  ·  %s" % entity.get_defeat_reason_label()
	_roll_result_label.text = (
		"Banked money cannot cover carried debt."
		if entity.get_defeat_reason() == Entity.DefeatReason.DEBT
		else "Your health reached zero."
	)
	_roll_result_label.show()
	refresh()


func _on_match_finished(winner: Entity) -> void:
	_turn_label.text = "Match Complete"
	_roll_result_label.text = (
		"You win  ·  Last player standing"
		if winner == _local_player
		else (
			"You lose  ·  %s" % _local_player.get_defeat_reason_label()
			if _local_player.is_defeated()
			else "%s wins  ·  Last player standing" % _get_participant_name(
				winner,
				_game_manager.participants.find(winner)
			)
		)
		if is_instance_valid(winner)
		else "The match ended without a winner."
	)
	_roll_result_label.show()
	refresh()


func _get_participant_name(entity: Entity, participant_index: int) -> String:
	if entity == _local_player:
		return "You"
	if is_instance_valid(entity):
		return entity.get_display_name()
	if participant_index >= 0:
		return "Participant %d" % (participant_index + 1)
	return "Unknown player"
