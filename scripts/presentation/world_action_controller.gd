class_name WorldActionController
extends Node

## Owns the in-world purchase/rent menu. It presents and submits commands, but
## GameManager remains the authority that accepts or rejects them.
const WORLD_MENU_HEIGHT := 2.15
const WORLD_MENU_SCREEN_GAP := 14.0
const WORLD_MENU_VIEWPORT_MARGIN := 12.0

var _game_manager: GameManager
var _game_camera: GameCamera
var _local_player: Entity
var _panel: PanelContainer
var _title: Label
var _details: Label
var _buy_button: Button
var _decline_button: Button
var _pay_rent_button: Button
var _configured := false


func configure(
	game_manager: GameManager,
	game_camera: GameCamera,
	local_player: Entity,
	panel: PanelContainer,
	title: Label,
	details: Label,
	buy_button: Button,
	decline_button: Button,
	pay_rent_button: Button
) -> void:
	_game_manager = game_manager
	_game_camera = game_camera
	_local_player = local_player
	_panel = panel
	_title = title
	_details = details
	_buy_button = buy_button
	_decline_button = decline_button
	_pay_rent_button = pay_rent_button
	_buy_button.pressed.connect(_on_buy_pressed)
	_decline_button.pressed.connect(_on_decline_pressed)
	_pay_rent_button.pressed.connect(_on_pay_rent_pressed)
	_game_manager.property_purchase_offered.connect(_on_purchase_offered)
	_game_manager.property_purchase_resolved.connect(_on_purchase_resolved)
	_game_manager.rent_payment_required.connect(_on_rent_required)
	_game_manager.rent_paid.connect(_on_rent_paid)
	_game_manager.turn_started.connect(_on_turn_started)
	_game_manager.roll_finished.connect(_on_roll_finished)
	_game_manager.match_finished.connect(_on_match_finished)
	_local_player.money_changed.connect(_on_local_money_changed)
	_configured = true
	refresh()


func _process(_delta: float) -> void:
	if _configured:
		_update_panel_position()


func refresh() -> void:
	if not _configured:
		return
	var active_entity := _game_manager.get_active_entity()
	var is_local_turn := active_entity == _local_player
	var is_resolving := _game_manager.is_turn_resolving()
	var pending_purchase := _game_manager.get_pending_purchase_plot()
	var pending_rent := _game_manager.get_pending_rent_plot()
	var has_purchase := is_local_turn and is_instance_valid(pending_purchase)
	var has_rent := is_local_turn and is_instance_valid(pending_rent)

	_panel.visible = has_purchase or has_rent
	_buy_button.visible = has_purchase
	_decline_button.visible = has_purchase
	_pay_rent_button.visible = has_rent
	_buy_button.disabled = (
		not has_purchase
		or is_resolving
		or _local_player.money < pending_purchase.get_buy_price()
	)
	_decline_button.disabled = not has_purchase or is_resolving
	_pay_rent_button.disabled = not has_rent or is_resolving
	if has_purchase:
		_buy_button.text = "Buy  $%d" % pending_purchase.get_buy_price()


func _on_buy_pressed() -> void:
	if _game_manager.request_property_purchase(_local_player, true):
		refresh()


func _on_decline_pressed() -> void:
	if _game_manager.request_property_purchase(_local_player, false):
		refresh()


func _on_pay_rent_pressed() -> void:
	if _game_manager.request_rent_payment(_local_player):
		refresh()


func _on_purchase_offered(
	entity: Entity,
	plot: Plot,
	buy_price: int,
	base_rent: int,
	tower_rent: int
) -> void:
	if entity == _local_player:
		_title.text = _get_plot_name(plot)
		_details.text = "Lap +$%d   ·   Hotel rent $%d" % [
			base_rent,
			tower_rent,
		]
		_buy_button.text = "Buy  $%d" % buy_price
		_decline_button.text = "Skip"
	refresh()


func _on_purchase_resolved(
	_entity: Entity,
	_plot: Plot,
	_purchased: bool,
	_price: int
) -> void:
	refresh()


func _on_rent_required(
	payer: Entity,
	owner: Entity,
	plot: Plot,
	amount: int
) -> void:
	if payer == _local_player:
		_title.text = _get_plot_name(plot)
		_details.text = "Owned by %s   ·   Rent due $%d" % [
			_get_participant_name(owner),
			amount,
		]
		_pay_rent_button.text = "Pay  $%d" % amount
	refresh()


func _on_rent_paid(
	_payer: Entity,
	_owner: Entity,
	_plot: Plot,
	_amount: int
) -> void:
	refresh()


func _on_turn_started(
	_entity: Entity,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	refresh()


func _on_roll_finished(
	_entity: Entity,
	_destination_index: int,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	refresh()


func _on_match_finished(_winner: Entity) -> void:
	refresh()


func _on_local_money_changed(_previous_money: int, _current_money: int) -> void:
	refresh()


func _update_panel_position() -> void:
	var active_entity := _game_manager.get_active_entity()
	var plot := _game_manager.get_pending_landing_action_plot()
	if active_entity != _local_player or not is_instance_valid(plot):
		_panel.visible = false
		return

	var anchor_position := plot.global_position + Vector3.UP * WORLD_MENU_HEIGHT
	if _game_camera.is_position_behind(anchor_position):
		_panel.visible = false
		return

	_panel.visible = true
	var screen_position := _game_camera.unproject_position(anchor_position)
	var panel_size := _panel.size
	var desired_position := screen_position + Vector2(
		-panel_size.x * 0.5,
		-panel_size.y - WORLD_MENU_SCREEN_GAP
	)
	var viewport_size := get_viewport().get_visible_rect().size
	desired_position.x = clampf(
		desired_position.x,
		WORLD_MENU_VIEWPORT_MARGIN,
		maxf(
			WORLD_MENU_VIEWPORT_MARGIN,
			viewport_size.x - panel_size.x - WORLD_MENU_VIEWPORT_MARGIN
		)
	)
	desired_position.y = clampf(
		desired_position.y,
		WORLD_MENU_VIEWPORT_MARGIN,
		maxf(
			WORLD_MENU_VIEWPORT_MARGIN,
			viewport_size.y - panel_size.y - WORLD_MENU_VIEWPORT_MARGIN
		)
	)
	_panel.position = desired_position


func _get_plot_name(plot: Plot) -> String:
	if not is_instance_valid(plot) or plot.data == null:
		return "this plot"
	return plot.data.display_name


func _get_participant_name(entity: Entity) -> String:
	if entity == _local_player:
		return "You"
	return entity.get_display_name() if is_instance_valid(entity) else "Unknown player"
