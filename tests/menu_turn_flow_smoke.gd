extends SceneTree

const GAME_SCENE := preload("res://play_scenes/test_scene.tscn")
const MENU_SCENE := preload("res://play_scenes/main_menu.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_menu_navigation()
	for participant_count in range(2, 5):
		await _test_participant_count(participant_count)

	if _failures.is_empty():
		print("PASS: menu and 2-4 player turn flow")
		quit()
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_menu_navigation() -> void:
	var menu := MENU_SCENE.instantiate()
	root.add_child(menu)
	await process_frame

	var main_panel := menu.get_node("MainPanel") as PanelContainer
	var setup_panel := menu.get_node("PlayerSetupPanel") as PanelContainer
	_expect(main_panel.visible, "The main menu should be visible on launch.")
	_expect(not setup_panel.visible, "The player setup should be hidden on launch.")

	var new_game_button := menu.get_node(
		"MainPanel/Margin/Content/NewGameButton"
	) as Button
	new_game_button.pressed.emit()
	_expect(not main_panel.visible, "New Game should hide the main menu panel.")
	_expect(setup_panel.visible, "New Game should show the player setup panel.")

	menu.queue_free()
	await process_frame


func _test_participant_count(participant_count: int) -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", participant_count)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var local_player := game_screen.get_node("Player") as Entity
	var rolled_entities: Array[Entity] = []
	game_manager.dice_rolled.connect(
		func(entity: Entity, _dice_values: Array[int]) -> void:
			rolled_entities.append(entity)
	)

	board.movement_units_per_second = 1000.0
	game_manager.ai_roll_delay = 0.01

	_expect(
		game_manager.participants.size() == participant_count,
		"A %d-player game should configure exactly %d participants." % [
			participant_count,
			participant_count,
		]
	)
	_expect(
		local_player.type == Entity.EntityType.PLAYER,
		"Player 1 should be human-controlled."
	)
	for index in range(1, game_manager.participants.size()):
		_expect(
			game_manager.participants[index].type == Entity.EntityType.AI,
			"Participant %d should be AI-controlled." % (index + 1)
		)

	_expect(
		not game_manager.request_end_turn(local_player),
		"A human turn should not end before its roll."
	)
	var fixed_roll: Array[int] = [1, 1]
	var destination := await game_manager.play_active_turn(fixed_roll)
	_expect(destination >= 0, "The human roll should complete board movement.")
	_expect(
		game_manager.get_active_entity() == local_player,
		"Finishing movement should not automatically end a human turn."
	)
	_expect(
		game_manager.request_end_turn(local_player),
		"End Turn should advance after human movement completes."
	)

	var deadline := Time.get_ticks_msec() + 5000
	while (
		game_manager.round_number < 2
		and Time.get_ticks_msec() < deadline
	):
		await process_frame

	_expect(
		game_manager.round_number == 2,
		"AI participants should roll and end their turns automatically."
	)
	_expect(
		game_manager.get_active_entity() == local_player,
		"A completed AI sequence should return control to Player 1."
	)
	_expect(
		rolled_entities.size() == participant_count,
		"Every configured participant should roll exactly once in round 1."
	)

	game_screen.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
