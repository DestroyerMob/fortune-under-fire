class_name CardHandController
extends Node

## Owns hand reveal, drag targeting, and card-command submission. CardView owns
## each face; GameManager validates and resolves every actual play.
const CARD_VIEW_SCRIPT := preload("res://scripts/presentation/card_view.gd")
const COLLAPSED_LIST_Y := 234.0
const REVEALED_LIST_Y := 10.0
const HAND_REVEAL_EDGE_HEIGHT := 48.0
const HAND_REVEAL_SECONDS := 0.2
const HAND_HIDE_DELAY_SECONDS := 0.16
const CARD_TAB_WIDTH := 184.0
const CARD_TAB_GAP := 14.0
const CARD_HAND_HORIZONTAL_PADDING := 28.0
const MINIMUM_CARD_SEPARATION := -112
const SELF_ZONE_SIZE := Vector2(330.0, 380.0)
const PROPERTY_DROP_RADIUS := 92.0

var _game_manager: GameManager
var _game_camera: GameCamera
var _local_player: Entity
var _hand: Control
var _card_list: HBoxContainer
var _play_in_progress := false
var _hand_revealed := false
var _hand_tween: Tween
var _hide_generation := 0
var _hide_scheduled := false
var _hovered_card_count := 0
var _dragging_card
var _drag_target_plot: Plot
var _drag_drop_valid := false


func configure(
	game_manager: GameManager,
	game_camera: GameCamera,
	local_player: Entity,
	hand: Control,
	card_list: HBoxContainer
) -> void:
	_game_manager = game_manager
	_game_camera = game_camera
	_local_player = local_player
	_hand = hand
	_card_list = card_list
	_card_list.position.y = COLLAPSED_LIST_Y
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


func set_local_player(local_player: Entity) -> void:
	if _local_player == local_player:
		refresh()
		return
	if is_instance_valid(_local_player):
		if _local_player.card_added.is_connected(_on_hand_changed):
			_local_player.card_added.disconnect(_on_hand_changed)
		if _local_player.card_removed.is_connected(_on_hand_changed):
			_local_player.card_removed.disconnect(_on_hand_changed)
		if _local_player.cards_cleared.is_connected(_on_cards_cleared):
			_local_player.cards_cleared.disconnect(_on_cards_cleared)
	_local_player = local_player
	if is_instance_valid(_local_player):
		_local_player.card_added.connect(_on_hand_changed)
		_local_player.card_removed.connect(_on_hand_changed)
		_local_player.cards_cleared.connect(_on_cards_cleared)
	_play_in_progress = false
	_dragging_card = null
	set_hand_revealed(false, true)
	_rebuild()


func _process(_delta: float) -> void:
	if not is_instance_valid(_hand) or not _hand.visible or _dragging_card != null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_position := get_viewport().get_mouse_position()
	var card_count := _card_list.get_child_count()
	var separation := _card_list.get_theme_constant(&"separation")
	var card_span := minf(
		_hand.size.x,
		CARD_TAB_WIDTH * card_count + separation * maxi(card_count - 1, 0)
	)
	var card_span_left := _hand.global_position.x + (_hand.size.x - card_span) * 0.5
	var horizontal_range := Rect2(
		Vector2(card_span_left, 0.0),
		Vector2(card_span, viewport_size.y)
	)
	var over_horizontal_hand := horizontal_range.has_point(mouse_position)
	var should_reveal := (
		over_horizontal_hand
		and mouse_position.y >= viewport_size.y - HAND_REVEAL_EDGE_HEIGHT
	)
	if _hovered_card_count > 0:
		should_reveal = true
	if _hand_revealed:
		should_reveal = (
			over_horizontal_hand
			and mouse_position.y >= _hand.global_position.y - 24.0
		)
	if should_reveal:
		_hide_generation += 1
		_hide_scheduled = false
		set_hand_revealed(true)
	elif _hand_revealed:
		_schedule_hand_hide()


func refresh() -> void:
	if not is_instance_valid(_hand):
		return
	_hand.visible = (
		is_instance_valid(_local_player)
		and _local_player.get_total_card_count() > 0
		and _game_manager.get_active_entity() == _local_player
		and _game_manager.state == GameManager.MatchState.ACTIVE
	)
	if not _hand.visible:
		set_hand_revealed(false, true)
	for child in _card_list.get_children():
		if not child.has_method(&"set_interactive"):
			continue
		var card_view = child
		var card := card_view.card_data as CardData
		if card == null:
			continue
		var interactive := (
			not _play_in_progress
			and _game_manager.get_active_entity() == _local_player
			and _game_manager.state == GameManager.MatchState.ACTIVE
		)
		card_view.set_interactive(
			interactive,
			"DRAG TO PLAY" if interactive else "PLAYING…"
		)


func set_hand_revealed(revealed: bool, immediate := false) -> void:
	if _hand_revealed == revealed and not immediate:
		return
	_hand_revealed = revealed
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	var target_y := REVEALED_LIST_Y if revealed else COLLAPSED_LIST_Y
	if immediate:
		_card_list.position.y = target_y
		return
	_hand_tween = create_tween()
	_hand_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hand_tween.tween_property(
		_card_list,
		^"position:y",
		target_y,
		HAND_REVEAL_SECONDS
	)


func get_self_cast_rect() -> Rect2:
	var viewport_size := get_viewport().get_visible_rect().size
	return Rect2(viewport_size * 0.5 - SELF_ZONE_SIZE * 0.5, SELF_ZONE_SIZE)


func is_hand_revealed() -> bool:
	return _hand_revealed


func _rebuild() -> void:
	if _play_in_progress:
		return
	_hovered_card_count = 0
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
	for card_index in cards.size():
		var card := cards[card_index]
		var card_view = CARD_VIEW_SCRIPT.new()
		card_view.configure(
			card,
			_local_player.get_card_quantity(card),
			card_index,
			cards.size()
		)
		card_view.drag_started.connect(_on_card_drag_started)
		card_view.drag_moved.connect(_on_card_drag_moved)
		card_view.drag_released.connect(_on_card_drag_released)
		card_view.hover_changed.connect(_on_card_hover_changed)
		_card_list.add_child(card_view)
		card_view.call_deferred(&"animate_in", card_index)
	_update_card_spacing(cards.size())
	refresh()


func _update_card_spacing(card_count: int) -> void:
	if card_count <= 1:
		_card_list.add_theme_constant_override(&"separation", CARD_TAB_GAP)
		return
	var available_width := maxf(
		_hand.size.x - CARD_HAND_HORIZONTAL_PADDING * 2.0,
		CARD_TAB_WIDTH
	)
	var fitted_separation := floori(
		(available_width - CARD_TAB_WIDTH * card_count) / float(card_count - 1)
	)
	_card_list.add_theme_constant_override(
		&"separation",
		clampi(fitted_separation, MINIMUM_CARD_SEPARATION, int(CARD_TAB_GAP))
	)


func _on_card_drag_started(card_view) -> void:
	if _play_in_progress or card_view == null:
		return
	card_view.prepare_for_drag()
	_dragging_card = card_view
	_drag_target_plot = null
	_drag_drop_valid = false
	_hide_generation += 1
	set_hand_revealed(true)
	for child in _card_list.get_children():
		if child != card_view:
			child.modulate.a = 0.28
	_update_drop_feedback(get_viewport().get_mouse_position())


func _on_card_hover_changed(_card_view, hovered: bool) -> void:
	_hovered_card_count = maxi(_hovered_card_count + (1 if hovered else -1), 0)
	if hovered:
		_hide_generation += 1
		_hide_scheduled = false
		set_hand_revealed(true)
	elif _hovered_card_count == 0 and _dragging_card == null:
		_schedule_hand_hide()


func _on_card_drag_moved(card_view, screen_position: Vector2) -> void:
	if card_view != _dragging_card:
		return
	_update_drop_feedback(screen_position)


func _on_card_drag_released(card_view, screen_position: Vector2) -> void:
	if card_view != _dragging_card:
		return
	_update_drop_feedback(screen_position)
	if not _drag_drop_valid:
		await card_view.animate_return_to_hand()
		_finish_drag(false)
		return

	var card := card_view.card_data as CardData
	var target_plot := _drag_target_plot
	if not _game_manager.can_target_card(_local_player, card, target_plot):
		card_view.set_drag_feedback(false, "CAN'T PLAY YET")
		await card_view.animate_return_to_hand()
		_finish_drag(false)
		return
	var drop_position := (
		_get_plot_screen_position(target_plot)
		if card.target_mode == CardData.TargetMode.PROPERTY
		else get_viewport().get_visible_rect().size * 0.5
	)
	_play_in_progress = true
	await card_view.animate_cast(
		drop_position,
		get_viewport().get_visible_rect().size
	)
	var played := await _game_manager.request_play_card(
		_local_player,
		card,
		target_plot
	)
	_play_in_progress = false
	_finish_drag(played)
	_rebuild()


func _update_drop_feedback(screen_position: Vector2) -> void:
	if _dragging_card == null:
		return
	var card := _dragging_card.card_data as CardData
	_drag_target_plot = null
	if card.target_mode == CardData.TargetMode.SELF:
		_drag_drop_valid = get_self_cast_rect().has_point(screen_position)
		_dragging_card.set_drag_feedback(
			_drag_drop_valid,
			"RELEASE TO PLAY" if _drag_drop_valid else "DRAG TO CENTRE"
		)
		return

	_drag_target_plot = _find_property_at_screen_position(screen_position)
	_drag_drop_valid = is_instance_valid(_drag_target_plot)
	_dragging_card.set_drag_feedback(
		_drag_drop_valid,
		"RELEASE TO PLAY" if _drag_drop_valid else "DRAG TO PROPERTY"
	)


func _find_property_at_screen_position(screen_position: Vector2) -> Plot:
	var closest_plot: Plot
	var closest_distance := PROPERTY_DROP_RADIUS
	for plot in _game_manager.board.plots:
		if plot.data == null or not plot.data.is_ownable():
			continue
		if _game_camera.is_position_behind(plot.global_position):
			continue
		var distance := screen_position.distance_to(_get_plot_screen_position(plot))
		if distance < closest_distance:
			closest_distance = distance
			closest_plot = plot
	return closest_plot


func _get_plot_screen_position(plot: Plot) -> Vector2:
	if not is_instance_valid(plot):
		return get_viewport().get_visible_rect().size * 0.5
	return _game_camera.unproject_position(plot.global_position + Vector3.UP * 0.2)


func _finish_drag(_played: bool) -> void:
	for child in _card_list.get_children():
		child.modulate.a = 1.0
	_dragging_card = null
	_drag_target_plot = null
	_drag_drop_valid = false
	_hide_generation += 1
	_schedule_hand_hide()
	refresh()


func _schedule_hand_hide() -> void:
	if _hide_scheduled:
		return
	_hide_scheduled = true
	_hide_generation += 1
	var generation := _hide_generation
	_hide_hand_after_delay(generation)


func _hide_hand_after_delay(generation: int) -> void:
	await get_tree().create_timer(HAND_HIDE_DELAY_SECONDS).timeout
	_hide_scheduled = false
	if generation == _hide_generation and _dragging_card == null:
		set_hand_revealed(false)


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
