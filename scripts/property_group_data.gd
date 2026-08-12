class_name PropertyGroupData
extends Resource

## Shared data for every property in a set. Future group-wide effects belong
## here so all plots in the group receive the same rules and presentation.
@export var display_name := "Property Group"
@export var color := Color.WHITE
@export_range(0, 10000, 1) var value := 0
