class_name PlotData
extends Resource

enum PlotType {CORNER, PROPERTY, UTILITY, CARD}

@export var display_name := "Plot"
@export var type: PlotType = PlotType.PROPERTY
@export var order := 0
@export_group("Property")
@export var property_group: PropertyGroupData
@export_group("Card")
@export var card_selector: CardSelector
@export_group("Presentation")
## Used by non-property plots. Property plots take their colour from their group.
@export var top_color := Color(0.72, 0.74, 0.78, 1.0)


func get_top_color() -> Color:
	if type == PlotType.PROPERTY and property_group != null:
		return property_group.color
	return top_color


func get_value() -> int:
	if type == PlotType.PROPERTY and property_group != null:
		return property_group.value
	return 0
