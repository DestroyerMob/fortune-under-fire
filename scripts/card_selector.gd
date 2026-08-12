class_name CardSelector
extends Resource

## The cards eligible to be awarded. Repeating a CardData entry gives that card
## a proportionally higher chance without requiring a separate weighting system.
@export var deck: Array[CardData] = []


## Pass an authoritative, seeded RNG when match determinism is required.
func draw_card(rng: RandomNumberGenerator = null) -> CardData:
	if deck.is_empty():
		push_warning("Cannot draw a card from an empty selector deck.")
		return null

	var selected_index := randi_range(0, deck.size() - 1)
	if rng != null:
		selected_index = rng.randi_range(0, deck.size() - 1)

	var selected_card := deck[selected_index]
	if selected_card == null:
		push_warning("The card selector deck contains an empty entry.")
	return selected_card
