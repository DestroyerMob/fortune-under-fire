class_name LocalPlayerHudController
extends Node

## Owns only the local player's persistent health and funds presentation.
var _player: Entity
var _money_label: Label
var _health_bar: ProgressBar
var _health_label: Label
var _money_change_tween: Tween
var _money_change_generation := 0


func configure(
	player: Entity,
	money_label: Label,
	health_bar: ProgressBar,
	health_label: Label
) -> void:
	_player = player
	_money_label = money_label
	_health_bar = health_bar
	_health_label = health_label
	if not _player.money_changed.is_connected(_on_money_changed):
		_player.money_changed.connect(_on_money_changed)
	if not _player.health_changed.is_connected(_on_health_changed):
		_player.health_changed.connect(_on_health_changed)
	_refresh_money()
	_refresh_health()


func _on_money_changed(previous_money: int, current_money: int) -> void:
	_play_money_change(current_money - previous_money)


func _on_health_changed(_previous_health: int, _current_health: int) -> void:
	_refresh_health()


func _refresh_money() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_money_label):
		return
	_money_label.text = "FUNDS  %s" % _format_money(_player.money)
	_money_label.modulate = (
		Color(1.0, 0.38, 0.32, 1.0)
		if _player.money < 0
		else Color.WHITE
	)


func _play_money_change(amount: int) -> void:
	if amount == 0:
		_refresh_money()
		return
	_money_change_generation += 1
	var generation := _money_change_generation
	if _money_change_tween != null and _money_change_tween.is_valid():
		_money_change_tween.kill()
	var sign_text := "+" if amount > 0 else "−"
	_money_label.text = "FUNDS  %s   %s$%d" % [
		_format_money(_player.money),
		sign_text,
		absi(amount),
	]
	_money_label.modulate = (
		Color(0.46, 1.0, 0.6, 1.0)
		if amount > 0
		else Color(1.0, 0.62, 0.28, 1.0)
	)
	_money_change_tween = create_tween().bind_node(_money_label)
	_money_change_tween.tween_property(
		_money_label,
		^"modulate",
		Color.WHITE,
		0.65
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_money_change_tween.tween_interval(0.2)
	_money_change_tween.tween_callback(
		func() -> void:
			if generation == _money_change_generation:
				_refresh_money()
	)


func _format_money(amount: int) -> String:
	return "−$%d" % absi(amount) if amount < 0 else "$%d" % amount


func _refresh_health() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_health_bar):
		return
	_health_bar.max_value = _player.max_health
	_health_bar.value = _player.health
	_health_label.text = "%d / %d" % [_player.health, _player.max_health]
