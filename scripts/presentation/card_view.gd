class_name CardView
extends Button

signal drag_started(card_view: CardView)
signal drag_moved(card_view: CardView, screen_position: Vector2)
signal drag_released(card_view: CardView, screen_position: Vector2)
signal hover_changed(card_view: CardView, hovered: bool)

## A single portrait card face and its local interaction animation. Gameplay
## legality and card effects remain outside this view.
const CARD_SIZE := Vector2(184.0, 238.0)
const HOVER_LIFT := 18.0
const DISABLED_HOVER_LIFT := 6.0
const MOTION_SECONDS := 0.16
const DRAG_THRESHOLD := 7.0

var card_data: CardData
var _accent := Color.WHITE
var _base_rotation := 0.0
var _base_z_index := 0
var _is_hovered := false
var _is_interactive := false
var _availability_text := "WAITING"
var _interaction_tween: Tween
var _status_label: Label
var _status_dot: Label
var _press_screen_position := Vector2.ZERO
var _drag_origin_global_position := Vector2.ZERO
var _drag_candidate := false
var _is_dragging := false
var _motion_locked := false


func configure(
	card: CardData,
	quantity: int,
	card_index: int,
	card_count: int
) -> void:
	card_data = card
	_accent = card.get_display_color()
	name = "Card%s" % String(card.card_id).to_pascal_case()
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pivot_offset = CARD_SIZE * 0.5
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = ""
	text = ""
	clip_text = false
	clip_contents = true
	flat = false
	_base_rotation = 0.0
	_base_z_index = card_index
	z_index = _base_z_index
	rotation = _base_rotation
	_set_card_styles()
	_build_face(quantity)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func set_interactive(interactive: bool, availability_text: String) -> void:
	_is_interactive = interactive
	_availability_text = availability_text
	disabled = not interactive
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if interactive
		else Control.CURSOR_FORBIDDEN
	)
	_refresh_status()


func get_status_text() -> String:
	return _status_label.text if is_instance_valid(_status_label) else ""


func is_being_dragged() -> bool:
	return _is_dragging


func prepare_for_drag() -> void:
	_motion_locked = false
	if not _is_dragging:
		_drag_origin_global_position = global_position
	_is_dragging = true
	_kill_interaction_tween()
	z_index = 1000
	rotation = 0.0
	scale = Vector2(1.07, 1.07)


func set_drag_feedback(valid_target: bool, target_text: String) -> void:
	if not _is_dragging or not is_instance_valid(_status_label):
		return
	_status_label.text = target_text
	var feedback_color := (
		Color(0.48, 1.0, 0.62, 1.0)
		if valid_target
		else Color(1.0, 0.52, 0.38, 1.0)
	)
	_status_label.add_theme_color_override(&"font_color", feedback_color)
	_status_dot.add_theme_color_override(&"font_color", feedback_color)


func animate_return_to_hand() -> void:
	_is_dragging = false
	_drag_candidate = false
	_motion_locked = true
	_kill_interaction_tween()
	_interaction_tween = create_tween().set_parallel(true)
	_interaction_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_interaction_tween.tween_property(
		self, ^"global_position", _drag_origin_global_position, 0.22
	)
	_interaction_tween.tween_property(self, ^"rotation", _base_rotation, 0.22)
	_interaction_tween.tween_property(self, ^"scale", Vector2(1.045, 1.045), 0.22)
	await _interaction_tween.finished
	_motion_locked = false
	_animate_interaction(_is_hovered)
	_refresh_status()


func animate_cast(drop_screen_position: Vector2, viewport_size: Vector2) -> void:
	_is_dragging = false
	_drag_candidate = false
	_motion_locked = true
	_kill_interaction_tween()
	var drop_top_left := drop_screen_position - size * 0.5
	_interaction_tween = create_tween().set_parallel(true)
	_interaction_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_interaction_tween.tween_property(self, ^"global_position", drop_top_left, 0.16)
	_interaction_tween.tween_property(self, ^"rotation", 0.0, 0.16)
	_interaction_tween.tween_property(self, ^"scale", Vector2(0.84, 0.84), 0.16)
	await _interaction_tween.finished
	if not is_instance_valid(self):
		return
	var flight_x := clampf(
		drop_screen_position.x + (drop_screen_position.x - viewport_size.x * 0.5) * 0.45,
		-size.x,
		viewport_size.x
	)
	var fly_target := Vector2(flight_x, -size.y - 70.0)
	_interaction_tween = create_tween().set_parallel(true)
	_interaction_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_interaction_tween.tween_property(self, ^"global_position", fly_target, 0.3)
	_interaction_tween.tween_property(
		self,
		^"rotation",
		deg_to_rad(18.0 if drop_screen_position.x >= viewport_size.x * 0.5 else -18.0),
		0.3
	)
	_interaction_tween.tween_property(self, ^"scale", Vector2(0.68, 0.68), 0.3)
	_interaction_tween.tween_property(self, ^"modulate:a", 0.12, 0.3)
	await _interaction_tween.finished
	_motion_locked = false


func _build_face(quantity: int) -> void:
	var top_edge := PanelContainer.new()
	top_edge.name = "AccentEdge"
	top_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_edge.add_theme_stylebox_override(
		&"panel", _create_accent_style(_accent)
	)
	add_child(top_edge)
	top_edge.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_edge.offset_left = 5.0
	top_edge.offset_top = 4.0
	top_edge.offset_right = -5.0
	top_edge.offset_bottom = 10.0

	var margin := MarginContainer.new()
	margin.name = "FaceMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 11)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_right", 11)
	margin.add_theme_constant_override(&"margin_bottom", 10)
	add_child(margin)

	var content := VBoxContainer.new()
	content.name = "CardFace"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", 4)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)

	var type_label := Label.new()
	type_label.name = "TypeLabel"
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.add_theme_color_override(&"font_color", _accent.lightened(0.42))
	type_label.add_theme_font_size_override(&"font_size", 10)
	type_label.text = CardData.CardType.keys()[card_data.type]
	header.add_child(type_label)

	var quantity_badge := PanelContainer.new()
	quantity_badge.name = "QuantityBadge"
	quantity_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_badge.add_theme_stylebox_override(
		&"panel",
		_create_badge_style(_accent)
	)
	header.add_child(quantity_badge)
	var quantity_label := Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.add_theme_font_size_override(&"font_size", 11)
	quantity_label.text = "×%d" % quantity
	quantity_badge.add_child(quantity_label)

	var title := Label.new()
	title.name = "TitleLabel"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override(&"font_color", Color(0.96, 0.97, 1.0, 1.0))
	title.add_theme_font_size_override(&"font_size", 17)
	title.text = card_data.display_name
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(title)

	var art_panel := PanelContainer.new()
	art_panel.name = "ArtPanel"
	art_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_panel.custom_minimum_size = Vector2(0.0, 62.0)
	art_panel.add_theme_stylebox_override(&"panel", _create_art_style(_accent))
	content.add_child(art_panel)
	var art_mark := Label.new()
	art_mark.name = "ArtMark"
	art_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_mark.add_theme_color_override(&"font_color", _accent.lightened(0.5))
	art_mark.add_theme_font_size_override(&"font_size", 32)
	art_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art_mark.text = _get_type_mark(card_data.type)
	art_panel.add_child(art_mark)

	var rule := Label.new()
	rule.name = "RuleLabel"
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(0.0, 44.0)
	rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rule.add_theme_color_override(&"font_color", Color(0.86, 0.88, 0.93, 1.0))
	rule.add_theme_font_size_override(&"font_size", 12)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.text = card_data.description
	content.add_child(rule)

	var divider := HSeparator.new()
	divider.name = "FooterDivider"
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_constant_override(&"separation", 2)
	content.add_child(divider)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override(&"separation", 5)
	content.add_child(footer)
	_status_dot = Label.new()
	_status_dot.name = "StatusDot"
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_dot.add_theme_font_size_override(&"font_size", 12)
	_status_dot.text = "●"
	footer.add_child(_status_dot)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override(&"font_size", 10)
	footer.add_child(_status_label)
	_refresh_status()


func _set_card_styles() -> void:
	add_theme_stylebox_override(&"normal", _create_card_style(false, false))
	add_theme_stylebox_override(&"hover", _create_card_style(true, false))
	add_theme_stylebox_override(&"pressed", _create_card_style(true, false))
	add_theme_stylebox_override(&"focus", _create_card_style(true, false))
	add_theme_stylebox_override(&"disabled", _create_card_style(false, true))


func _create_card_style(hovered: bool, is_disabled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _accent.darkened(0.72)
	if hovered:
		style.bg_color = _accent.darkened(0.66)
	if is_disabled:
		style.bg_color = _accent.darkened(0.82)
		style.bg_color.a = 0.96
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = _accent.lightened(0.26 if hovered else 0.06)
	if is_disabled:
		style.border_color = _accent.darkened(0.48)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.52 if hovered else 0.36)
	style.shadow_size = 8 if hovered else 4
	style.shadow_offset = Vector2(0.0, 4.0 if hovered else 2.0)
	style.content_margin_left = 1.0
	style.content_margin_top = 1.0
	style.content_margin_right = 1.0
	style.content_margin_bottom = 1.0
	return style


func _create_accent_style(card_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color.lightened(0.12)
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style


func _create_art_style(card_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color.darkened(0.55)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = card_color.lightened(0.08)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_right = 9
	style.corner_radius_bottom_left = 9
	return style


func _create_badge_style(card_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color.darkened(0.45)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = card_color.lightened(0.22)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _refresh_status() -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = (
		"DRAG TO PLAY"
		if _is_interactive and _is_hovered
		else _availability_text
	)
	var status_color := (
		_accent.lightened(0.45)
		if _is_interactive
		else Color(0.48, 0.5, 0.56, 1.0)
	)
	_status_label.add_theme_color_override(&"font_color", status_color)
	_status_dot.add_theme_color_override(&"font_color", status_color)


func _on_mouse_entered() -> void:
	_is_hovered = true
	hover_changed.emit(self, true)
	_refresh_status()
	if not _motion_locked:
		_animate_interaction(true)


func _on_mouse_exited() -> void:
	_is_hovered = false
	hover_changed.emit(self, false)
	_refresh_status()
	if not _motion_locked:
		_animate_interaction(false)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var mouse_event := event as InputEventMouse
	var screen_position: Vector2 = (
		get_global_transform_with_canvas() * mouse_event.position
	)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _is_interactive:
				return
			_press_screen_position = screen_position
			_drag_origin_global_position = global_position
			_drag_candidate = true
			accept_event()
		elif _drag_candidate:
			_drag_candidate = false
			if _is_dragging:
				drag_released.emit(self, screen_position)
			else:
				_animate_interaction(_is_hovered)
			accept_event()
	elif event is InputEventMouseMotion and _drag_candidate:
		if (
			not _is_dragging
			and screen_position.distance_to(_press_screen_position) >= DRAG_THRESHOLD
		):
			prepare_for_drag()
			drag_started.emit(self)
		if _is_dragging:
			global_position = screen_position - size * 0.5
			drag_moved.emit(self, screen_position)
		accept_event()


func _animate_interaction(hovered: bool) -> void:
	_kill_interaction_tween()
	z_index = 100 + _base_z_index if hovered else _base_z_index
	var lift := 0.0
	var target_scale := Vector2.ONE
	if hovered:
		lift = HOVER_LIFT if _is_interactive else DISABLED_HOVER_LIFT
		target_scale = Vector2(1.045, 1.045) if _is_interactive else Vector2(1.015, 1.015)
	_interaction_tween = create_tween().set_parallel(true)
	_interaction_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_interaction_tween.tween_property(self, ^"position:y", -lift, MOTION_SECONDS)
	_interaction_tween.tween_property(self, ^"scale", target_scale, MOTION_SECONDS)
	_interaction_tween.tween_property(
		self,
		^"rotation",
		0.0 if hovered else _base_rotation,
		MOTION_SECONDS
	)


func _animate_scale(target_scale: Vector2, duration: float) -> void:
	_kill_interaction_tween()
	_interaction_tween = create_tween()
	_interaction_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_interaction_tween.tween_property(self, ^"scale", target_scale, duration)


func animate_in(card_index: int) -> void:
	if not is_inside_tree():
		return
	modulate.a = 0.0
	scale = Vector2(0.9, 0.9)
	position.y = 28.0
	var entrance := create_tween().set_parallel(true)
	entrance.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var delay := 0.035 * float(card_index)
	entrance.tween_property(self, ^"position:y", 0.0, 0.22).set_delay(delay)
	entrance.tween_property(self, ^"scale", Vector2.ONE, 0.22).set_delay(delay)
	entrance.tween_property(self, ^"modulate:a", 1.0, 0.14).set_delay(delay)


func _kill_interaction_tween() -> void:
	if _interaction_tween != null and _interaction_tween.is_valid():
		_interaction_tween.kill()
	_interaction_tween = null


func _get_type_mark(card_type: CardData.CardType) -> String:
	match card_type:
		CardData.CardType.MOVEMENT:
			return "»"
		CardData.CardType.SUPPORT:
			return "+"
	return "✦"
