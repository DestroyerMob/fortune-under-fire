class_name Plot
extends Node3D

signal card_awarded(entity: Entity, card: CardData)
signal purchase_offered(entity: Entity)
signal purchased(entity: Entity, price: int)
signal rent_due(payer: Entity, owner: Entity, amount: int)
signal rent_paid(payer: Entity, owner: Entity, amount: int)
signal owner_changed(previous_owner: Entity, current_owner: Entity)
signal building_changed(previous_building: BuildingData, current_building: BuildingData)
signal building_constructed(owner: Entity, building: BuildingData, cost: int)
signal bank_balance_changed(previous_balance: int, current_balance: int)

@export var data: PlotData
@export var plot_owner: Entity
@export_category("Economy")
@export_range(-1, 1000000, 1) var base_rent := -1
@export_range(-1, 1000000, 1) var tower_rent := -1
@export_range(0, 1000000, 1) var buy_price := 0
@export_category("Upgrades")
@export var building: BuildingData
## Compatibility flag for older prototype scenes and tests.
@export var has_tower := false

var _presenter: PlotPresenter
var bank_balance := 0


func _ready() -> void:
	_presenter = PlotPresenter.new()
	_presenter.configure(self)


func on_land(entity: Entity) -> void:
	if data != null and data.type == PlotData.PlotType.CARD:
		_award_card(entity)
		return
	if plot_owner != null and not is_instance_valid(plot_owner):
		set_plot_owner(null)
	if is_instance_valid(plot_owner):
		if entity == plot_owner:
			on_owner_land(entity)
		else:
			on_trespasser_land(entity)
	else:
		on_unowned_land(entity)


func on_owner_land(_entity: Entity) -> void:
	pass


func on_trespasser_land(entity: Entity) -> void:
	if can_collect_rent_from(entity):
		rent_due.emit(entity, plot_owner, get_rent_value())


func on_unowned_land(entity: Entity) -> void:
	if can_be_purchased_by(entity):
		purchase_offered.emit(entity)


func can_be_purchased_by(entity: Entity) -> bool:
	return (
		is_instance_valid(entity)
		and not is_instance_valid(plot_owner)
		and data != null
		and data.is_ownable()
		and buy_price > 0
	)


func purchase(entity: Entity) -> bool:
	if not can_be_purchased_by(entity) or not entity.spend_money(buy_price):
		return false
	set_plot_owner(entity)
	purchased.emit(entity, buy_price)
	return true


func can_construct_building(
	entity: Entity,
	building_data: BuildingData,
	cost_override := -1
) -> bool:
	var effective_cost := (
		cost_override if cost_override >= 0 else building_data.build_cost
	) if building_data != null else 0
	return (
		is_instance_valid(entity)
		and plot_owner == entity
		and building == null
		and building_data != null
		and data != null
		and data.is_ownable()
		and entity.money >= effective_cost
	)


func construct_building(
	entity: Entity,
	building_data: BuildingData,
	cost_override := -1
) -> bool:
	var effective_cost := (
		cost_override if cost_override >= 0 else building_data.build_cost
	) if building_data != null else 0
	if (
		not can_construct_building(entity, building_data, effective_cost)
		or not entity.spend_money(effective_cost)
	):
		return false
	set_building(building_data)
	building_constructed.emit(entity, building_data, effective_cost)
	return true


func set_building(building_data: BuildingData) -> void:
	var previous_building := building
	if previous_building == building_data:
		return
	if (
		previous_building != null
		and previous_building.type == BuildingData.BuildingType.BANK
		and (
			building_data == null
			or building_data.type != BuildingData.BuildingType.BANK
		)
	):
		set_bank_balance(0)
	building = building_data
	refresh_building_visuals()
	building_changed.emit(previous_building, building)


func clear_building() -> void:
	set_building(null)
	has_tower = false
	refresh_building_visuals()


func has_building_type(building_type: BuildingData.BuildingType) -> bool:
	return building != null and building.type == building_type


func can_collect_rent_from(entity: Entity) -> bool:
	return (
		is_instance_valid(entity)
		and is_instance_valid(plot_owner)
		and entity != plot_owner
		and get_rent_value() > 0
	)


func pay_rent(entity: Entity) -> int:
	if not can_collect_rent_from(entity):
		return -1
	var payment := get_rent_value()
	if payment > 0 and not entity.pay_obligation(payment):
		return -1
	plot_owner.add_money(payment)
	rent_paid.emit(entity, plot_owner, payment)
	return payment


func set_plot_owner(entity: Entity) -> void:
	var previous_owner := plot_owner
	if previous_owner == entity:
		return
	if previous_owner != entity and bank_balance > 0:
		set_bank_balance(0)
	plot_owner = entity
	refresh_owner_visuals()
	owner_changed.emit(previous_owner, plot_owner)


func reset_ownership() -> void:
	set_plot_owner(null)


func get_property_value() -> int:
	return get_base_rent()


func get_base_rent() -> int:
	if base_rent >= 0:
		return base_rent
	return data.get_value() if data != null else 0


func get_tower_rent() -> int:
	return tower_rent if tower_rent >= 0 else get_base_rent() * 2


func get_rent_value() -> int:
	if has_building_type(BuildingData.BuildingType.MEDIC_TOWER):
		return 0
	return (
		get_tower_rent()
		if has_tower or has_building_type(BuildingData.BuildingType.HOTEL)
		else get_base_rent()
	)


func get_buy_price() -> int:
	return buy_price


func get_bank_balance() -> int:
	return bank_balance


func set_bank_balance(value: int) -> void:
	var previous_balance := bank_balance
	bank_balance = maxi(value, 0)
	if previous_balance != bank_balance:
		bank_balance_changed.emit(previous_balance, bank_balance)


func can_manage_bank(entity: Entity) -> bool:
	return (
		is_instance_valid(entity)
		and plot_owner == entity
		and has_building_type(BuildingData.BuildingType.BANK)
	)


func deposit_to_bank(entity: Entity, amount: int) -> bool:
	if not can_manage_bank(entity) or amount <= 0:
		return false
	if not entity.spend_money(amount):
		return false
	set_bank_balance(bank_balance + amount)
	return true


func withdraw_from_bank(entity: Entity, amount: int) -> bool:
	if not can_manage_bank(entity) or amount <= 0 or amount > bank_balance:
		return false
	set_bank_balance(bank_balance - amount)
	entity.add_money(amount)
	return true


func credit_bank_interest() -> int:
	if (
		building == null
		or building.type != BuildingData.BuildingType.BANK
		or building.interest_rate_percent <= 0
		or bank_balance <= 0
	):
		return 0
	var interest := floori(
		float(bank_balance * building.interest_rate_percent) / 100.0
	)
	if interest > 0:
		set_bank_balance(bank_balance + interest)
	return interest


func set_has_tower(value: bool) -> void:
	has_tower = value
	refresh_building_visuals()


## Presentation compatibility wrappers keep callers independent of the current
## presenter implementation while Plot remains the domain aggregate.
func refresh_visuals() -> void:
	if _presenter != null:
		_presenter.refresh_plot()


func refresh_owner_visuals() -> void:
	if _presenter != null:
		_presenter.refresh_owner()


func refresh_tower_visuals() -> void:
	refresh_building_visuals()


func refresh_building_visuals() -> void:
	if _presenter != null:
		_presenter.refresh_building()


func play_building_activation() -> void:
	if _presenter != null:
		_presenter.play_building_activation()


func _award_card(entity: Entity) -> void:
	if data.card_selector == null:
		push_warning("Card plot '%s' has no card selector assigned." % name)
		return
	var selected_card := data.card_selector.draw_card()
	if selected_card != null and entity.add_card(selected_card):
		card_awarded.emit(entity, selected_card)
