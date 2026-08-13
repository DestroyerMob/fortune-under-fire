class_name CardPlayResult
extends RefCounted

enum Outcome {
	TURN_ENDED,
	ADDITIONAL_ROLL_GRANTED,
	MOVED_TO_HOSPITAL,
}

var actor: Entity
var card: CardData
var outcome: Outcome
var destination_index := -1


func _init(
	resolved_actor: Entity,
	resolved_card: CardData,
	resolved_outcome: Outcome,
	resolved_destination_index := -1
) -> void:
	actor = resolved_actor
	card = resolved_card
	outcome = resolved_outcome
	destination_index = resolved_destination_index
