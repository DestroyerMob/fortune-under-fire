class_name OwnedPropertyRailController
extends Node

signal selection_changed(previous_plot: Plot, current_plot: Plot)

const DEED_SIZE := Vector2(292.0, 60.0)
const DEED_VISIBLE_TAB_WIDTH := 24.0
const DEED_SLIDE_SECONDS := 0.2
const DEED_HOVER_SETTLE_SECONDS := 0.08
const DEED_EXIT_GRACE_SECONDS := 0.08

var _game_manager: GameManager
var _board: Board
var _game_camera: GameCamera
var _local_player: Entity
var _rail: Control
var _list: VBoxContainer
var _previewed_property: Plot
var _hover_candidate_property: Plot
var _hover_generation := 0
var _selected_property: Plot
var _selected_deed: Button


func configure(
	game_manager: GameManager,
	game_camera: GameCamera,
	local_player: Entity,
	rail: Control,
	list: VBoxContainer
) -> void:
	_game_manager = game_manager
	_board = game_manager.board
	_game_camera = game_camera
	_local_player = local_player
	_rail = rail
	_list = list
	_board.movement_started.connect(_on_movement_started)
	_game_manager.dice_rolled.connect(_on_dice_rolled)
	_game_manager.turn_finished.connect(_on_turn_finished)
	_game_manager.match_finished.connect(_on_match_finished)
	for plot in _board.plots:
		plot.owner_changed.connect(_on_owner_changed.bind(plot))
		plot.building_changed.connect(_on_building_changed.bind(plot))
		plot.bank_balance_changed.connect(_on_bank_balance_changed.bind(plot))


func refresh_owned_properties() -> void:
	cancel_preview(true)
	clear_selection()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var owned_properties := _board.get_owned_properties(_local_player)
	_rail.visible = not owned_properties.is_empty()
	for plot in owned_properties:
		_list.add_child(_create_deed(plot))


func get_selected_property() -> Plot:
	if (
		is_instance_valid(_selected_property)
		and _selected_property.plot_owner == _local_player
	):
		return _selected_property
	return null


func clear_selection() -> void:
	var previous_property := get_selected_property()
	if is_instance_valid(_selected_deed):
		_selected_deed.button_pressed = false
		_set_deed_revealed(_selected_deed, false)
	_selected_deed = null
	_selected_property = null
	if is_instance_valid(previous_property):
		selection_changed.emit(previous_property, null)


func refresh_plot(plot: Plot) -> void:
	for slot in _list.get_children():
		if slot.get_child_count() == 0:
			continue
		var deed := slot.get_child(0) as Button
		if deed != null and deed.has_meta(&"plot") and deed.get_meta(&"plot") == plot:
			deed.text = _get_deed_text(plot, _board.plots.find(plot))
			return


func cancel_preview(
	snap_to_player: bool,
	prefer_selected_property := false,
	force_active_player := false
) -> void:
	_hover_generation += 1
	_hover_candidate_property = null
	if (
		not is_instance_valid(_previewed_property)
		and not prefer_selected_property
		and not snap_to_player
		and not force_active_player
	):
		_previewed_property = null
		return

	_previewed_property = null
	var selected_property := get_selected_property()
	if prefer_selected_property and is_instance_valid(selected_property):
		_game_camera.track_target(selected_property, snap_to_player)
		return
	var active_entity := _game_manager.get_active_entity()
	if is_instance_valid(active_entity):
		_game_camera.focus_turn_target(active_entity, snap_to_player)
	elif is_instance_valid(_local_player):
		_game_camera.track_target(_local_player, snap_to_player)


func _create_deed(plot: Plot) -> Control:
	var deed_slot := Control.new()
	var deed := Button.new()
	var plot_index := _board.plots.find(plot)
	deed_slot.name = "PropertyDeedSlot%d" % plot_index
	deed_slot.custom_minimum_size = Vector2(DEED_VISIBLE_TAB_WIDTH, DEED_SIZE.y)
	deed_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deed.name = "PropertyDeed%d" % plot_index
	deed.custom_minimum_size = DEED_SIZE
	deed.size = DEED_SIZE
	deed.position.x = _get_hidden_deed_x()
	deed.text = _get_deed_text(plot, plot_index)
	deed.alignment = HORIZONTAL_ALIGNMENT_LEFT
	deed.focus_mode = Control.FOCUS_NONE
	deed.toggle_mode = true
	deed.tooltip_text = ""
	deed.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	deed.set_meta(&"plot", plot)
	deed.add_theme_font_size_override(&"font_size", 13)
	var deed_color := plot.data.get_top_color()
	deed.add_theme_stylebox_override(
		&"normal", _create_deed_style(deed_color, false, false)
	)
	deed.add_theme_stylebox_override(
		&"hover", _create_deed_style(deed_color, true, false)
	)
	deed.add_theme_stylebox_override(
		&"pressed", _create_deed_style(deed_color, true, true)
	)
	deed.add_theme_stylebox_override(
		&"focus", _create_deed_style(deed_color, true, true)
	)
	deed.mouse_entered.connect(_on_deed_mouse_entered.bind(deed, plot))
	deed.mouse_exited.connect(_on_deed_mouse_exited.bind(deed, plot))
	deed.pressed.connect(_on_deed_pressed.bind(deed, plot))
	deed_slot.add_child(deed)
	return deed_slot


func _get_deed_text(plot: Plot, _plot_index: int) -> String:
	var site_status := (
		plot.building.display_name
		if plot.building != null
		else "Unbuilt"
	)
	if plot.has_building_type(BuildingData.BuildingType.BANK):
		site_status = "Bank · $%d stored" % plot.get_bank_balance()
	return "%s  ·  %s\nLap +$%d    Rent $%d" % [
		_get_plot_name(plot),
		site_status,
		plot.get_base_rent(),
		plot.get_rent_value(),
	]


func _on_bank_balance_changed(
	_previous_balance: int,
	_current_balance: int,
	plot: Plot
) -> void:
	refresh_plot(plot)


func _create_deed_style(
	property_color: Color,
	hovered: bool,
	selected: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.10, 0.12, 0.17, 0.97)
		if not hovered
		else (
			Color(0.20, 0.22, 0.29, 1.0)
			if selected
			else Color(0.16, 0.18, 0.24, 0.99)
		)
	)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 9 if selected else 7
	style.border_width_bottom = 1
	style.border_color = property_color.lightened(
		0.3 if selected else (0.18 if hovered else 0.0)
	)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.content_margin_left = 12.0
	style.content_margin_right = 10.0
	return style


func _get_hidden_deed_x() -> float:
	return -(DEED_SIZE.x - DEED_VISIBLE_TAB_WIDTH)


func _set_deed_revealed(deed: Button, revealed: bool) -> void:
	if not is_instance_valid(deed):
		return
	var active_tween: Tween
	if deed.has_meta(&"slide_tween"):
		active_tween = deed.get_meta(&"slide_tween") as Tween
	if active_tween != null and active_tween.is_valid():
		active_tween.kill()
	var slide_tween := deed.create_tween()
	slide_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide_tween.tween_property(
		deed,
		^"position:x",
		0.0 if revealed else _get_hidden_deed_x(),
		DEED_SLIDE_SECONDS
	)
	deed.set_meta(&"slide_tween", slide_tween)


func _on_deed_mouse_entered(deed: Button, plot: Plot) -> void:
	_set_deed_revealed(deed, true)
	_hover_generation += 1
	_hover_candidate_property = plot
	if (
		not is_instance_valid(plot)
		or plot.plot_owner != _local_player
		or _game_manager.is_turn_resolving()
		or _board.is_any_entity_moving()
	):
		_hover_candidate_property = null
		return
	if _previewed_property == plot:
		return
	_focus_after_hover_settles(plot, _hover_generation)


func _focus_after_hover_settles(plot: Plot, expected_generation: int) -> void:
	await get_tree().create_timer(DEED_HOVER_SETTLE_SECONDS).timeout
	if (
		expected_generation != _hover_generation
		or _hover_candidate_property != plot
		or not is_instance_valid(plot)
		or plot.plot_owner != _local_player
		or _game_manager.is_turn_resolving()
		or _board.is_any_entity_moving()
	):
		return
	_previewed_property = plot
	_game_camera.track_target(plot)


func _on_deed_mouse_exited(deed: Button, plot: Plot) -> void:
	if deed != _selected_deed:
		_set_deed_revealed(deed, false)
	if _hover_candidate_property == plot:
		_hover_candidate_property = null
		_hover_generation += 1
	if _previewed_property == plot:
		_restore_camera_after_exit(_hover_generation)


func _on_deed_pressed(deed: Button, plot: Plot) -> void:
	if (
		not is_instance_valid(deed)
		or not is_instance_valid(plot)
		or plot.plot_owner != _local_player
	):
		return

	if _selected_deed == deed and not deed.button_pressed:
		clear_selection()
		cancel_preview(false, false, true)
		return

	var previous_property := get_selected_property()
	if is_instance_valid(_selected_deed) and _selected_deed != deed:
		_selected_deed.button_pressed = false
		_set_deed_revealed(_selected_deed, false)
	_selected_deed = deed
	_selected_property = plot
	deed.button_pressed = true
	_set_deed_revealed(deed, true)
	if previous_property != plot:
		selection_changed.emit(previous_property, plot)
	if not _game_manager.is_turn_resolving() and not _board.is_any_entity_moving():
		_previewed_property = plot
		_game_camera.track_target(plot)


func _restore_camera_after_exit(expected_generation: int) -> void:
	await get_tree().create_timer(DEED_EXIT_GRACE_SECONDS).timeout
	if expected_generation == _hover_generation:
		cancel_preview(false, true)


func _on_owner_changed(
	_previous_owner: Entity,
	_current_owner: Entity,
	_plot: Plot
) -> void:
	refresh_owned_properties()


func _on_building_changed(
	_previous_building: BuildingData,
	_current_building: BuildingData,
	plot: Plot
) -> void:
	refresh_plot(plot)


func _on_dice_rolled(_entity: Entity, _dice_values: Array[int]) -> void:
	cancel_preview(true)


func _on_movement_started(
	_entity: Entity,
	_spaces: int,
	_destination_index: int
) -> void:
	cancel_preview(true)


func _on_turn_finished(
	entity: Entity,
	_destination_index: int,
	_participant_index: int,
	_round_number: int,
	_turn_number: int
) -> void:
	cancel_preview(true)
	if entity == _local_player:
		clear_selection()


func _on_match_finished(_winner: Entity) -> void:
	cancel_preview(true)
	clear_selection()


func _get_plot_name(plot: Plot) -> String:
	if not is_instance_valid(plot) or plot.data == null:
		return "this plot"
	return plot.data.display_name
