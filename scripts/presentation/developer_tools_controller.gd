class_name DeveloperToolsController
extends Node

## Routes local developer shortcuts through explicit authority commands. The
## enabled flag is a local setting and never becomes authoritative match state.
var _game_manager: GameManager
var _game_session: Node
var _toast: Label
var _toast_tween: Tween


func configure(game_manager: GameManager, game_session: Node, toast: Label) -> void:
	_game_manager = game_manager
	_game_session = game_session
	_toast = toast
	_toast.hide()


func try_handle_input(event: InputEvent) -> bool:
	if not event.is_action_pressed(&"dev_grant_card"):
		return false
	if event is InputEventKey and event.echo:
		return true
	grant_random_card()
	return true


func grant_random_card() -> CardData:
	if not bool(_game_session.get("dev_options_enabled")):
		return null
	var active_player := _game_manager.get_active_entity()
	var card := _game_manager.debug_grant_random_card(active_player)
	if card != null:
		_show_toast("DEV  ·  +%s" % card.display_name)
	return card


func _show_toast(message: String) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = message
	_toast.modulate = Color(1.0, 0.82, 0.42, 1.0)
	_toast.show()
	_toast_tween = create_tween().bind_node(_toast)
	_toast_tween.tween_interval(0.8)
	_toast_tween.tween_property(_toast, ^"modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(_toast.hide)
