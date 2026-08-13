class_name BuildingData
extends Resource

enum BuildingType {
	APARTMENTS,
	HOTEL,
	CASINO,
	GUN_TOWER,
	ARTILLERY_BATTERY,
	TESLA_COIL,
	MEDIC_TOWER,
	BANK,
}

enum Category {MONEY, DAMAGE, SUPPORT}

@export var building_id: StringName
@export var display_name := "Building"
@export_multiline var description := ""
@export var type: BuildingType
@export var category: Category
@export_range(0, 1000000, 1) var build_cost := 100
## Lap bonus for Apartments, or payout per die pip for Casinos.
@export_range(0, 1000000, 1) var money_value := 0
## Base damage for weapon buildings.
@export_range(0, 10000, 1) var damage := 0
@export_range(0, 10000, 1) var healing := 0
## Percentage of stored balance credited to a Bank account each lap.
@export_range(0, 100, 1, "suffix:%") var interest_rate_percent := 0
## Circular board range for Artillery support or Tesla connections.
@export_range(0, 1000, 1) var range_spaces := 0
@export var color := Color.WHITE


func is_money_building() -> bool:
	return category == Category.MONEY


func get_effect_summary() -> String:
	match type:
		BuildingType.APARTMENTS:
			return "+$%d each lap" % money_value
		BuildingType.HOTEL:
			return "Charges tower rent"
		BuildingType.CASINO:
			return "Roll 1–6: $%d per point" % money_value
		BuildingType.GUN_TOWER:
			return "%d damage on landing" % damage
		BuildingType.ARTILLERY_BATTERY:
			return "%d damage within %d plots" % [damage, range_spaces]
		BuildingType.TESLA_COIL:
			return "%d damage per connected coil" % damage
		BuildingType.MEDIC_TOWER:
			return "Heals owner %d on landing" % healing
		BuildingType.BANK:
			return "%d%% interest on stored money each lap" % interest_rate_percent
	return description
