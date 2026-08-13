class_name PropertyActionSystem
extends Node

## Owns the one pending property action and the purchase/rent transaction path.
## Match/turn validation stays at the GameManager facade.
signal purchase_offered(
	entity: Entity,
	plot: Plot,
	buy_price: int,
	base_rent: int,
	tower_rent: int
)
signal purchase_resolved(entity: Entity, plot: Plot, purchased: bool, price: int)
signal rent_required(payer: Entity, owner: Entity, plot: Plot, amount: int)
signal rent_paid(payer: Entity, owner: Entity, plot: Plot, amount: int)

var _board: Board
var _can_offer_action: Callable
var _pending_action: LandingAction
var _is_configured := false


func configure(board: Board, can_offer_action: Callable) -> void:
	_board = board
	_can_offer_action = can_offer_action
	if _is_configured:
		return
	_is_configured = true
	for plot in _board.plots:
		var purchase_callback := _on_purchase_offered.bind(plot)
		if not plot.purchase_offered.is_connected(purchase_callback):
			plot.purchase_offered.connect(purchase_callback)
		var rent_due_callback := _on_rent_due.bind(plot)
		if not plot.rent_due.is_connected(rent_due_callback):
			plot.rent_due.connect(rent_due_callback)
		var rent_paid_callback := _on_rent_paid.bind(plot)
		if not plot.rent_paid.is_connected(rent_paid_callback):
			plot.rent_paid.connect(rent_paid_callback)


func clear_pending_action() -> void:
	_pending_action = null


func has_pending_action() -> bool:
	return _get_pending_action() != null


func get_pending_plot() -> Plot:
	var action := _get_pending_action()
	return action.plot if action != null else null


func get_pending_purchase_plot() -> Plot:
	var action := _get_pending_action()
	if action != null and action.kind == LandingAction.Kind.PURCHASE:
		return action.plot
	return null


func get_pending_rent_plot() -> Plot:
	var action := _get_pending_action()
	if action != null and action.kind == LandingAction.Kind.RENT:
		return action.plot
	return null


func resolve_purchase(entity: Entity, should_purchase: bool) -> bool:
	var action := _get_pending_action()
	if (
		action == null
		or action.kind != LandingAction.Kind.PURCHASE
		or action.actor != entity
	):
		return false
	var plot := action.plot
	if not plot.can_be_purchased_by(entity):
		_finish_purchase(entity, plot, false)
		return false
	if should_purchase:
		# Failed affordability deliberately leaves the offer open so End Turn can
		# still decline it or another future effect can change the balance.
		if not plot.purchase(entity):
			return false
		_finish_purchase(entity, plot, true)
		return true
	_finish_purchase(entity, plot, false)
	return true


func pay_rent(entity: Entity) -> bool:
	var action := _get_pending_action()
	if (
		action == null
		or action.kind != LandingAction.Kind.RENT
		or action.actor != entity
	):
		return false
	if not action.plot.can_collect_rent_from(entity):
		clear_pending_action()
		return false
	# Plot emits rent_paid synchronously; _on_rent_paid clears this action.
	return action.plot.pay_rent(entity) >= 0


func _get_pending_action() -> LandingAction:
	if _pending_action == null:
		return null
	if not is_instance_valid(_pending_action.actor) or not is_instance_valid(_pending_action.plot):
		_pending_action = null
	return _pending_action


func _on_purchase_offered(entity: Entity, plot: Plot) -> void:
	if has_pending_action() or not bool(_can_offer_action.call(entity)):
		return
	_pending_action = LandingAction.new(LandingAction.Kind.PURCHASE, entity, plot)
	purchase_offered.emit(
		entity,
		plot,
		plot.get_buy_price(),
		plot.get_base_rent(),
		plot.get_tower_rent()
	)


func _on_rent_due(
	payer: Entity,
	owner: Entity,
	amount: int,
	plot: Plot
) -> void:
	if has_pending_action() or not bool(_can_offer_action.call(payer)):
		return
	_pending_action = LandingAction.new(
		LandingAction.Kind.RENT,
		payer,
		plot,
		owner,
		amount
	)
	rent_required.emit(payer, owner, plot, amount)


func _on_rent_paid(
	payer: Entity,
	owner: Entity,
	amount: int,
	plot: Plot
) -> void:
	var action := _get_pending_action()
	if (
		action != null
		and action.kind == LandingAction.Kind.RENT
		and action.actor == payer
		and action.plot == plot
	):
		clear_pending_action()
	rent_paid.emit(payer, owner, plot, amount)


func _finish_purchase(entity: Entity, plot: Plot, purchased: bool) -> void:
	clear_pending_action()
	purchase_resolved.emit(entity, plot, purchased, plot.get_buy_price())
