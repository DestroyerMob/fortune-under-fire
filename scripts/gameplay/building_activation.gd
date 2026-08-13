class_name BuildingActivation
extends RefCounted

## A typed result produced by BuildingEffectSystem. Keeping effect data together
## prevents every new building field from changing a long positional signal.
enum EffectKind {LAP_INCOME, RENT_INCOME, BANK_INTEREST, DAMAGE, HEALING}

var kind: EffectKind
var owner: Entity
var source_plot: Plot
var building: BuildingData
var target: Entity
var amount: int
var die_roll: int


func _init(
	effect_kind: EffectKind,
	effect_owner: Entity,
	effect_source_plot: Plot,
	effect_building: BuildingData,
	effect_target: Entity = null,
	effect_amount := 0,
	effect_die_roll := 0
) -> void:
	kind = effect_kind
	owner = effect_owner
	source_plot = effect_source_plot
	building = effect_building
	target = effect_target
	amount = effect_amount
	die_roll = effect_die_roll


func get_money_amount() -> int:
	return (
		amount
		if kind in [
			EffectKind.LAP_INCOME,
			EffectKind.RENT_INCOME,
			EffectKind.BANK_INTEREST,
		]
		else 0
	)


func get_damage_amount() -> int:
	return amount if kind == EffectKind.DAMAGE else 0


func get_healing_amount() -> int:
	return amount if kind == EffectKind.HEALING else 0
