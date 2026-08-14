class_name BuildingPaletteController
extends Node

const BUILD_PANEL_BOTTOM_OFFSET := -130.0
const BUILDING_MANAGER_BOTTOM := 240.0
const BANK_MANAGER_BOTTOM := 390.0

## Contextual plot manager. Empty owned plots show construction choices; plots
## with a building show its management view. Commands always pass through the
## GameManager authority facade.
var _game_manager: GameManager
var _local_player: Entity
var _property_rail: OwnedPropertyRailController
var _palette: PanelContainer
var _manager_title: Label
var _target_label: Label
var _status_label: Label
var _description_label: Label
var _building_scroll: ScrollContainer
var _button_list: VBoxContainer
var _bank_controls: VBoxContainer
var _bank_balance_label: Label
var _bank_interest_label: Label
var _bank_amount: SpinBox
var _deposit_button: Button
var _withdraw_button: Button
var _selected_property: Plot
var _bank_delta_tween: Tween
var _bank_delta_generation := 0


func configure(
	game_manager: GameManager,
	local_player: Entity,
	property_rail: OwnedPropertyRailController,
	palette: PanelContainer,
	manager_title: Label,
	target_label: Label,
	status_label: Label,
	description_label: Label,
	building_scroll: ScrollContainer,
	button_list: VBoxContainer,
	bank_controls: VBoxContainer,
	bank_balance_label: Label,
	bank_interest_label: Label,
	bank_amount: SpinBox,
	deposit_button: Button,
	withdraw_button: Button
) -> void:
	_game_manager = game_manager
	_local_player = local_player
	_property_rail = property_rail
	_palette = palette
	_manager_title = manager_title
	_target_label = target_label
	_status_label = status_label
	_description_label = description_label
	_building_scroll = building_scroll
	_button_list = button_list
	_bank_controls = bank_controls
	_bank_balance_label = bank_balance_label
	_bank_interest_label = bank_interest_label
	_bank_amount = bank_amount
	_deposit_button = deposit_button
	_withdraw_button = withdraw_button
	_property_rail.selection_changed.connect(_on_selection_changed)
	_game_manager.building_constructed.connect(_on_building_constructed)
	_game_manager.turn_started.connect(_on_turn_started)
	_game_manager.dice_rolled.connect(_on_dice_rolled)
	_game_manager.roll_finished.connect(_on_roll_finished)
	_game_manager.property_purchase_offered.connect(_on_purchase_offered)
	_game_manager.property_purchase_resolved.connect(_on_purchase_resolved)
	_game_manager.rent_payment_required.connect(_on_rent_required)
	_game_manager.rent_paid.connect(_on_rent_paid)
	_game_manager.bank_transaction_completed.connect(_on_bank_transaction)
	_game_manager.bank_interest_credited.connect(_on_bank_interest)
	_game_manager.complete_sets_changed.connect(_on_complete_sets_changed)
	_local_player.money_changed.connect(_on_money_changed)
	_bank_amount.value_changed.connect(_on_bank_amount_changed)
	_deposit_button.pressed.connect(_on_deposit_pressed)
	_withdraw_button.pressed.connect(_on_withdraw_pressed)
	for plot in _game_manager.board.plots:
		plot.building_changed.connect(_on_plot_building_changed.bind(plot))
		plot.bank_balance_changed.connect(_on_bank_balance_changed.bind(plot))
	_populate()
	refresh()


func set_local_player(local_player: Entity) -> void:
	if is_instance_valid(_local_player):
		if _local_player.money_changed.is_connected(_on_money_changed):
			_local_player.money_changed.disconnect(_on_money_changed)
	_local_player = local_player
	_selected_property = _property_rail.get_selected_property()
	if is_instance_valid(_local_player):
		if not _local_player.money_changed.is_connected(_on_money_changed):
			_local_player.money_changed.connect(_on_money_changed)
	_cancel_bank_delta()
	refresh()


func refresh() -> void:
	var selected_property := get_selected_property()
	if not is_instance_valid(selected_property):
		_palette.hide()
		return

	var can_manage := (
		_game_manager.state == GameManager.MatchState.ACTIVE
		and _game_manager.get_active_entity() == _local_player
		and not _local_player.is_defeated()
		and not _game_manager.is_turn_resolving()
		and not _game_manager.has_pending_movement_adjustment()
		and not _game_manager.has_pending_landing_action()
		and selected_property.plot_owner == _local_player
	)
	_palette.visible = can_manage
	if not can_manage:
		return

	_target_label.text = _get_plot_name(selected_property)
	var has_building := selected_property.building != null
	var is_bank := (
		has_building
		and selected_property.has_building_type(BuildingData.BuildingType.BANK)
	)
	_set_panel_mode(has_building, is_bank)
	_manager_title.text = "MANAGE" if has_building else "BUILD"
	_building_scroll.visible = not has_building
	_status_label.visible = has_building
	_description_label.visible = has_building and not is_bank
	_bank_controls.visible = is_bank

	if has_building:
		_status_label.text = selected_property.building.display_name
		_description_label.text = selected_property.building.get_effect_summary()
		if is_bank:
			_refresh_bank_manager(selected_property)
	else:
		_status_label.text = "Unbuilt"
		_description_label.text = ""

	for child in _button_list.get_children():
		var button := child as Button
		if button == null:
			continue
		var building: BuildingData
		if button.has_meta(&"building"):
			building = button.get_meta(&"building") as BuildingData
		var building_cost := _game_manager.get_building_cost(
			_local_player,
			building
		)
		if building != null:
			button.text = "%s   $%d\n%s" % [
				building.display_name,
				building_cost,
				building.get_effect_summary(),
			]
		button.disabled = (
			has_building
			or building == null
			or _local_player.money < building_cost
		)


func _set_panel_mode(has_building: bool, is_bank: bool) -> void:
	_palette.anchor_bottom = 0.0 if has_building else 1.0
	_palette.offset_bottom = (
		(BANK_MANAGER_BOTTOM if is_bank else BUILDING_MANAGER_BOTTOM)
		if has_building
		else BUILD_PANEL_BOTTOM_OFFSET
	)


func get_selected_property() -> Plot:
	if (
		is_instance_valid(_selected_property)
		and _selected_property.plot_owner == _local_player
	):
		return _selected_property
	return null


func _refresh_bank_manager(plot: Plot) -> void:
	if _bank_delta_tween == null or not _bank_delta_tween.is_valid():
		_bank_balance_label.text = "STORED  $%d" % plot.get_bank_balance()
		_bank_balance_label.modulate = Color.WHITE
	_bank_interest_label.text = "%d%% interest when you pass Start" % (
		plot.building.interest_rate_percent
	)
	var amount := maxi(int(_bank_amount.value), 1)
	_deposit_button.text = "Deposit  $%d" % amount
	_withdraw_button.text = "Withdraw  $%d" % amount
	_deposit_button.disabled = amount > _local_player.money
	_withdraw_button.disabled = amount > plot.get_bank_balance()


func _populate() -> void:
	for child in _button_list.get_children():
		child.queue_free()
	for building in _game_manager.available_buildings:
		if building == null:
			continue
		var button := Button.new()
		button.name = "Build%sButton" % String(building.building_id).to_pascal_case()
		button.custom_minimum_size = Vector2(228.0, 46.0)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s   $%d\n%s" % [
			building.display_name,
			building.build_cost,
			building.get_effect_summary(),
		]
		button.set_meta(&"building", building)
		button.add_theme_font_size_override(&"font_size", 12)
		button.add_theme_stylebox_override(
			&"normal",
			_create_button_style(building.color, false)
		)
		button.add_theme_stylebox_override(
			&"hover",
			_create_button_style(building.color, true)
		)
		button.add_theme_stylebox_override(
			&"pressed",
			_create_button_style(building.color, true)
		)
		button.pressed.connect(_on_building_button_pressed.bind(building))
		_button_list.add_child(button)


func _create_button_style(building_color: Color, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.10, 0.12, 0.17, 0.97)
		if not hovered
		else Color(0.17, 0.19, 0.25, 0.99)
	)
	style.border_width_left = 5
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = building_color.lightened(0.12 if hovered else 0.0)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.content_margin_left = 10.0
	style.content_margin_right = 8.0
	return style


func _on_building_button_pressed(building: BuildingData) -> void:
	var selected_property := get_selected_property()
	if not is_instance_valid(selected_property):
		return
	if _game_manager.request_construct_building(
		_local_player,
		selected_property,
		building
	):
		refresh()


func _on_deposit_pressed() -> void:
	var plot := get_selected_property()
	if is_instance_valid(plot):
		_game_manager.request_bank_deposit(
			_local_player,
			plot,
			maxi(int(_bank_amount.value), 1)
		)
	refresh()


func _on_withdraw_pressed() -> void:
	var plot := get_selected_property()
	if is_instance_valid(plot):
		_game_manager.request_bank_withdrawal(
			_local_player,
			plot,
			maxi(int(_bank_amount.value), 1)
		)
	refresh()


func _on_selection_changed(_previous_plot: Plot, current_plot: Plot) -> void:
	_cancel_bank_delta()
	_selected_property = current_plot
	refresh()


func _on_building_constructed(
	_owner: Entity,
	_plot: Plot,
	_building: BuildingData,
	_cost: int
) -> void:
	refresh()


func _on_complete_sets_changed(
	entity: Entity,
	_controlled_sets: Array[PropertyGroupData]
) -> void:
	if entity == _local_player:
		refresh()


func _on_plot_building_changed(
	_previous_building: BuildingData,
	_current_building: BuildingData,
	_plot: Plot
) -> void:
	refresh()


func _on_bank_balance_changed(
	_previous_balance: int,
	_current_balance: int,
	plot: Plot
) -> void:
	_property_rail.refresh_plot(plot)
	refresh()


func _on_bank_amount_changed(_value: float) -> void:
	refresh()


func _on_bank_transaction(
	entity: Entity,
	plot: Plot,
	kind: StringName,
	amount: int,
	new_balance: int
) -> void:
	refresh()
	if entity == _local_player and plot == get_selected_property():
		_play_bank_delta(
			-amount if kind == &"withdrawal" else amount,
			new_balance
		)


func _on_bank_interest(
	owner: Entity,
	plot: Plot,
	amount: int,
	new_balance: int
) -> void:
	refresh()
	if owner == _local_player and plot == get_selected_property():
		_play_bank_delta(amount, new_balance)


func _play_bank_delta(amount: int, new_balance: int) -> void:
	if amount == 0 or not is_instance_valid(_bank_balance_label):
		return
	_cancel_bank_delta()
	_bank_delta_generation += 1
	var generation := _bank_delta_generation
	_bank_balance_label.text = "STORED  $%d   %s$%d" % [
		new_balance,
		"+" if amount > 0 else "−",
		absi(amount),
	]
	_bank_balance_label.modulate = (
		Color(0.46, 1.0, 0.6, 1.0)
		if amount > 0
		else Color(1.0, 0.62, 0.28, 1.0)
	)
	_bank_delta_tween = create_tween().bind_node(_bank_balance_label)
	_bank_delta_tween.tween_property(
		_bank_balance_label,
		^"modulate",
		Color.WHITE,
		0.65
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bank_delta_tween.tween_interval(0.2)
	_bank_delta_tween.tween_callback(
		func() -> void:
			if generation == _bank_delta_generation:
				_bank_delta_tween = null
				refresh()
	)


func _cancel_bank_delta() -> void:
	_bank_delta_generation += 1
	if _bank_delta_tween != null and _bank_delta_tween.is_valid():
		_bank_delta_tween.kill()
	_bank_delta_tween = null


func _on_turn_started(
	_entity: Entity,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	refresh()


func _on_dice_rolled(_entity: Entity, _dice_values: Array[int]) -> void:
	refresh()


func _on_roll_finished(
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


func _on_money_changed(_previous_money: int, _current_money: int) -> void:
	refresh()


func _get_plot_name(plot: Plot) -> String:
	if not is_instance_valid(plot) or plot.data == null:
		return "this plot"
	return plot.data.display_name
