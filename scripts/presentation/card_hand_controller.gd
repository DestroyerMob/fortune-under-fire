class_name CardHandController
extends Node

## Owns the local hand's rounded card presentation. It reads playability from
## GameManager and submits card commands; it never removes cards or applies an
## effect itself.
const CARD_SIZE := Vector2(170.0, 104.0)

var _game_manager: GameManager
var _local_player: Entity
var _hand: Control
var _card_list: HBoxContainer
var _play_in_progress := false


func configure(
	game_manager: GameManager,
	local_player: Entity,
	hand: Control,
	card_list: HBoxContainer
) -> void:
	_game_manager = game_manager
	_local_player = local_player
	_hand = hand
	_card_list = card_list
	_local_player.card_added.connect(_on_hand_changed)
	_local_player.card_removed.connect(_on_hand_changed)
	_local_player.cards_cleared.connect(_on_cards_cleared)
	_game_manager.turn_started.connect(_on_turn_state_changed)
	_game_manager.dice_rolled.connect(_on_dice_rolled)
	_game_manager.roll_finished.connect(_on_roll_finished)
	_game_manager.property_purchase_offered.connect(_on_purchase_offered)
	_game_manager.property_purchase_resolved.connect(_on_purchase_resolved)
	_game_manager.rent_payment_required.connect(_on_rent_required)
	_game_manager.rent_paid.connect(_on_rent_paid)
	_game_manager.card_play_started.connect(_on_card_play_started)
	_game_manager.card_played.connect(_on_card_played)
	_game_manager.match_finished.connect(_on_match_finished)
	_rebuild()


func refresh() -> void:
	if not is_instance_valid(_hand):
		return
	_hand.visible = _local_player.get_total_card_count() > 0
	for child in _card_list.get_children():
		var card_button := child as Button
		if card_button == null or not card_button.has_meta(&"card"):
			continue
		var card := card_button.get_meta(&"card") as CardData
		card_button.disabled = (
			_play_in_progress
			or not _game_manager.can_play_card(_local_player, card)
		)


func _rebuild() -> void:
	for child in _card_list.get_children():
		_card_list.remove_child(child)
		child.queue_free()

	var cards: Array[CardData] = []
	for card_variant in _local_player.hand.keys():
		var card := card_variant as CardData
		if card != null:
			cards.append(card)
	cards.sort_custom(
		func(first: CardData, second: CardData) -> bool:
			return String(first.card_id) < String(second.card_id)
	)
	for card in cards:
		_card_list.add_child(_create_card(card))
	refresh()


func _create_card(card: CardData) -> Button:
	var card_button := Button.new()
	card_button.name = "Card%s" % String(card.card_id).to_pascal_case()
	card_button.custom_minimum_size = CARD_SIZE
	card_button.focus_mode = Control.FOCUS_NONE
	card_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card_button.tooltip_text = ""
	card_button.set_meta(&"card", card)
	card_button.add_theme_stylebox_override(
		&"normal", _create_card_style(card.get_display_color(), false, false)
	)
	card_button.add_theme_stylebox_override(
		&"hover", _create_card_style(card.get_display_color(), true, false)
	)
	card_button.add_theme_stylebox_override(
		&"pressed", _create_card_style(card.get_display_color(), true, false)
	)
	card_button.add_theme_stylebox_override(
		&"disabled", _create_card_style(card.get_display_color(), false, true)
	)
	card_button.pressed.connect(_on_card_pressed.bind(card))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 11)
	margin.add_theme_constant_override(&"margin_top", 9)
	margin.add_theme_constant_override(&"margin_right", 11)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	card_button.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", 3)
	margin.add_child(content)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_row)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 15)
	title.text = card.display_name
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(title)
	var quantity := Label.new()
	quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity.add_theme_font_size_override(&"font_size", 13)
	quantity.modulate = Color(1.0, 1.0, 1.0, 0.78)
	quantity.text = "×%d" % _local_player.get_card_quantity(card)
	title_row.add_child(quantity)

	var description := Label.new()
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override(&"font_size", 12)
	description.modulate = Color(1.0, 1.0, 1.0, 0.86)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = card.description
	content.add_child(description)

	var type_label := Label.new()
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_label.add_theme_font_size_override(&"font_size", 10)
	type_label.modulate = Color(1.0, 1.0, 1.0, 0.62)
	type_label.text = CardData.CardType.keys()[card.type]
	content.add_child(type_label)
	return card_button


func _create_card_style(
	card_color: Color,
	hovered: bool,
	disabled: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color.darkened(0.34 if not hovered else 0.2)
	if disabled:
		style.bg_color = style.bg_color.darkened(0.28)
		style.bg_color.a = 0.78
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = card_color.lightened(0.22 if hovered else 0.06)
	if disabled:
		style.border_color = style.border_color.darkened(0.4)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4 if hovered else 0.24)
	style.shadow_size = 7 if hovered else 4
	return style


func _on_card_pressed(card: CardData) -> void:
	if _play_in_progress:
		return
	_play_in_progress = true
	refresh()
	await _game_manager.request_play_card(_local_player, card)
	_play_in_progress = false
	_rebuild()


func _on_hand_changed(
	_card: CardData,
	_quantity: int,
	_total_card_count: int
) -> void:
	_rebuild()


func _on_cards_cleared() -> void:
	_rebuild()


func _on_turn_state_changed(
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


func _on_card_play_started(_entity: Entity, _card: CardData) -> void:
	refresh()


func _on_card_played(_result) -> void:
	refresh()


func _on_match_finished(_winner: Entity) -> void:
	refresh()
