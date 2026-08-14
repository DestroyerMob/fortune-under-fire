class_name PropertyGroupData
extends Resource

enum ControlBonus {
	INDUSTRIAL_EFFICIENCY,
	LIVING_WARD,
	GUIDED_CURRENT,
	INTELLIGENCE_NETWORK,
	SOVEREIGN_CLAIM,
	TRIBUTE,
	OVERCHARGE,
	MASTERWORK_COMMISSION,
}

## Shared identity, presentation, and complete-control rule for one five-plot
## set. Runtime ownership and consumable uses belong to SetBonusSystem.
@export var group_id: StringName
@export var display_name := "Property Group"
@export var color := Color.WHITE
## Backward-compatible default for plots without a plot-specific value.
@export_range(0, 10000, 1) var value := 0
@export_group("Complete Control")
@export_range(1, 20, 1) var complete_set_size := 5
@export var control_bonus: ControlBonus
@export var control_bonus_name := "Set Power"
@export_multiline var control_bonus_description := ""
## Primary tuning value: normally a percentage, or one movement space for
## Guided Current. Balance remains data rather than system code.
@export_range(0, 1000, 1) var control_bonus_value := 0


func get_control_summary() -> String:
	return "%s — %s" % [control_bonus_name, control_bonus_description]
