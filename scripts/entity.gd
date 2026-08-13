class_name Entity
extends MeshInstance3D

signal card_added(card: CardData, new_quantity: int, total_card_count: int)
signal card_removed(card: CardData, remaining_quantity: int, total_card_count: int)
signal cards_cleared()
signal health_changed(previous_health: int, current_health: int)
signal money_changed(previous_money: int, current_money: int)
signal defeated(entity: Entity)

enum EntityType {PLAYER, AI}
enum DefeatReason {NONE, HEALTH, DEBT}

@export var type: EntityType
@export var color: Color
@export var display_name := ""
@export_range(0.0, 5.0, 0.05) var plot_vertical_offset := 0.75
@export_category("Starting Stats")
@export_range(1, 10000, 1) var max_health := 100
@export_range(0, 1000000, 1) var starting_money := 1200
@export_category("Cards")
@export var hand: Dictionary[CardData, int] = {}

var health := 100
var money := 1200
var defeat_reason: DefeatReason = DefeatReason.NONE
var _presenter: EntityPresenter


func _ready() -> void:
	_presenter = EntityPresenter.new()
	_presenter.configure(self)


func roll_dice() -> Array[int]:
	return [randi_range(1, 6), randi_range(1, 6)]


## Kept as a compatibility wrapper while callers migrate to roll_dice().
func _roll() -> Array[int]:
	return roll_dice()


func get_display_name() -> String:
	if not display_name.strip_edges().is_empty():
		return display_name
	if not name.is_empty():
		return String(name)
	return "Entity"


func reset_for_match(clear_hand := true) -> void:
	defeat_reason = DefeatReason.NONE
	set_health(max_health)
	set_money(starting_money)
	if clear_hand and not hand.is_empty():
		hand.clear()
		cards_cleared.emit()


func set_health(value: int) -> void:
	var previous_health := health
	health = clampi(value, 0, max_health)
	if health == previous_health:
		return
	if _presenter != null:
		_presenter.refresh_health()
	health_changed.emit(previous_health, health)
	if health == 0:
		_mark_defeated(DefeatReason.HEALTH)


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
	return defeat_reason != DefeatReason.NONE or health <= 0 or money < 0


func get_defeat_reason() -> DefeatReason:
	return defeat_reason


func get_defeat_reason_label() -> String:
	match defeat_reason:
		DefeatReason.HEALTH:
			return "Health depleted"
		DefeatReason.DEBT:
			return "In debt"
	return "Still standing"


func set_money(value: int) -> void:
	var previous_money := money
	money = value
	if money != previous_money:
		money_changed.emit(previous_money, money)
	if money < 0:
		_mark_defeated(DefeatReason.DEBT)


func add_money(amount: int) -> bool:
	if amount <= 0:
		return false
	set_money(money + amount)
	return true


func spend_money(amount: int) -> bool:
	if amount < 0 or amount > money or is_defeated():
		return false
	if amount == 0:
		return true
	set_money(money - amount)
	return true


## Mandatory payments differ from voluntary spending: the full obligation is
## paid even when it creates debt, which immediately eliminates the entity.
func pay_obligation(amount: int) -> bool:
	if amount < 0 or is_defeated():
		return false
	if amount == 0:
		return true
	set_money(money - amount)
	return true


func _mark_defeated(reason: DefeatReason) -> void:
	if defeat_reason != DefeatReason.NONE or reason == DefeatReason.NONE:
		return
	defeat_reason = reason
	defeated.emit(self)


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
	return 0 if card == null else hand.get(card, 0)


func get_total_card_count() -> int:
	var total := 0
	for quantity in hand.values():
		total += quantity
	return total


## Presentation compatibility methods. Gameplay systems publish outcomes; the
## feedback controller chooses when to call these local visual operations.
func play_money_feedback(amount: int, _reason := "") -> void:
	if _presenter != null:
		_presenter.play_money_feedback(amount)


func play_damage_feedback(amount: int) -> void:
	if _presenter != null:
		_presenter.play_damage_feedback(amount)


func play_healing_feedback(amount: int) -> void:
	if _presenter != null:
		_presenter.play_healing_feedback(amount)


func get_active_feedback_count() -> int:
	return _presenter.get_active_feedback_count() if _presenter != null else 0


func has_active_feedback_kind(kind: StringName) -> bool:
	return _presenter != null and _presenter.has_active_feedback_kind(kind)


func get_health_indicator() -> Node3D:
	return _presenter.get_health_indicator() if _presenter != null else null


func get_health_indicator_ratio() -> float:
	return float(health) / float(maxi(max_health, 1))
