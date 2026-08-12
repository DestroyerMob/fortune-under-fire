class_name Entity
extends MeshInstance3D

signal card_added(card: CardData, new_quantity: int, total_card_count: int)
signal card_removed(card: CardData, remaining_quantity: int, total_card_count: int)

enum EntityType {PLAYER, AI}

@export var type: EntityType
@export var color: Color
## Height above a plot's origin when this entity is placed by the Board.
@export_range(0.0, 5.0, 0.05) var plot_vertical_offset := 0.75
## Acquired cards keyed by their data resource, with the number held as value.
@export var hand: Dictionary[CardData, int] = {}

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.35
	material_override = material

func _roll() -> Array[int]:
	var die1 := randi_range(1, 6)
	var die2 := randi_range(1, 6)
	return [die1, die2]


func add_card(card: CardData, quantity := 1) -> bool:
	if card == null:
		push_warning("Cannot add an empty card to %s's hand." % name)
		return false
	if quantity <= 0:
		push_warning("Card quantity added to a hand must be positive.")
		return false

	var new_quantity := get_card_quantity(card) + quantity
	hand[card] = new_quantity
	card_added.emit(card, new_quantity, get_total_card_count())
	return true


func remove_card(card: CardData, quantity := 1) -> bool:
	if card == null or quantity <= 0 or get_card_quantity(card) < quantity:
		return false

	var remaining_quantity := get_card_quantity(card) - quantity
	if remaining_quantity == 0:
		hand.erase(card)
	else:
		hand[card] = remaining_quantity

	card_removed.emit(card, remaining_quantity, get_total_card_count())
	return true


func get_card_quantity(card: CardData) -> int:
	if card == null:
		return 0
	return hand.get(card, 0)


func get_total_card_count() -> int:
	var total := 0
	for quantity in hand.values():
		total += quantity
	return total
