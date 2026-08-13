class_name LandingAction
extends RefCounted

## The single unresolved choice/payment created by landing on a property.
enum Kind {PURCHASE, RENT}

var kind: Kind
var actor: Entity
var plot: Plot
var counterparty: Entity
var quoted_amount: int


func _init(
	action_kind: Kind,
	action_actor: Entity,
	action_plot: Plot,
	action_counterparty: Entity = null,
	action_amount := 0
) -> void:
	kind = action_kind
	actor = action_actor
	plot = action_plot
	counterparty = action_counterparty
	quoted_amount = action_amount
