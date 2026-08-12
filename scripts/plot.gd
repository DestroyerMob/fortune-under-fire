class_name Plot
extends Node3D

signal card_awarded(entity: Entity, card: CardData)

@export var data: PlotData
@export var plot_owner: Entity

@onready var _top_mesh := get_node_or_null(^"Top") as MeshInstance3D


func _ready() -> void:
	refresh_visuals()


## Applies plot data without altering the shared lower board material.
func refresh_visuals() -> void:
	if _top_mesh == null or data == null:
		return

	var top_material := StandardMaterial3D.new()
	top_material.albedo_color = data.get_top_color()
	top_material.roughness = 0.55
	_top_mesh.material_override = top_material

## This decides which landing behaviour to choose
func on_land(entity: Entity) -> void:
	if data != null and data.type == PlotData.PlotType.CARD:
		_award_card(entity)
		return

	if plot_owner != null:
		if entity == plot_owner:
			on_owner_land(entity)
		else:
			on_trespasser_land(entity)
	else:
		on_unowned_land(entity)

## This is what happens when a plot is owned and the owner lands on it
func on_owner_land(_entity: Entity) -> void:
	pass

## This is what happens when a plot is owned but someone who's not the owner lands on it
func on_trespasser_land(_entity: Entity) -> void:
	pass

## This is what happens when an unowned plot is landed on
func on_unowned_land(_entity: Entity) -> void:
	pass


func get_property_value() -> int:
	if data == null:
		return 0
	return data.get_value()


func _award_card(entity: Entity) -> void:
	if data.card_selector == null:
		push_warning("Card plot '%s' has no card selector assigned." % name)
		return

	var selected_card := data.card_selector.draw_card()
	if selected_card != null and entity.add_card(selected_card):
		card_awarded.emit(entity, selected_card)
