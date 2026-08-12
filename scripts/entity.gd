class_name Entity
extends MeshInstance3D

signal card_added(card: CardData, new_quantity: int, total_card_count: int)
signal card_removed(card: CardData, remaining_quantity: int, total_card_count: int)
signal health_changed(previous_health: int, current_health: int)
signal money_changed(previous_money: int, current_money: int)
signal defeated(entity: Entity)

enum EntityType {PLAYER, AI}

@export var type: EntityType
@export var color: Color
## Height above a plot's origin when this entity is placed by the Board.
@export_range(0.0, 5.0, 0.05) var plot_vertical_offset := 0.75
@export_category("Starting Stats")
@export_range(1, 10000, 1) var max_health := 100
@export_range(0, 1000000, 1) var starting_money := 200
@export_category("Cards")
## Acquired cards keyed by their data resource, with the number held as value.
@export var hand: Dictionary[CardData, int] = {}

var health := 100
var money := 200


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.35
	material_override = material


func roll_dice() -> Array[int]:
	var die1 := randi_range(1, 6)
	var die2 := randi_range(1, 6)
	return [die1, die2]


## Kept as a compatibility wrapper while callers migrate to roll_dice().
func _roll() -> Array[int]:
	return roll_dice()


func reset_for_match(clear_hand := true) -> void:
	set_health(max_health)
	set_money(starting_money)
	if clear_hand:
		hand.clear()


func set_health(value: int) -> void:
	var previous_health := health
	health = clampi(value, 0, max_health)
	if health == previous_health:
		return

	health_changed.emit(previous_health, health)
	if health == 0:
		defeated.emit(self)


func take_damage(amount: int) -> int:
	if amount <= 0 or is_defeated():
		return 0

	var previous_health := health
	set_health(health - amount)
	return previous_health - health


func heal(amount: int) -> int:
	if amount <= 0 or is_defeated():
		return 0

	var previous_health := health
	set_health(health + amount)
	return health - previous_health


func is_defeated() -> bool:
	return health <= 0


func set_money(value: int) -> void:
	var previous_money := money
	money = maxi(value, 0)
	if money != previous_money:
		money_changed.emit(previous_money, money)


func add_money(amount: int) -> bool:
	if amount <= 0:
		return false
	set_money(money + amount)
	return true


func spend_money(amount: int) -> bool:
	if amount < 0 or amount > money:
		return false
	if amount == 0:
		return true

	set_money(money - amount)
	return true


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
