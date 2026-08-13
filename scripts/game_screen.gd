extends Node3D

signal property_deed_selection_changed(previous_plot: Plot, current_plot: Plot)

@onready var game_manager: GameManager = $GameManager
@onready var game_camera: GameCamera = $Camera3D
@onready var local_player: Entity = $Player
@onready var available_participants: Array[Entity] = [
	$Player,
	$Player2,
	$Player3,
	$Player4,
]
@onready var local_hud: LocalPlayerHudController = %LocalPlayerHudController
@onready var turn_hud: TurnHudController = %TurnHudController
@onready var world_actions: WorldActionController = %WorldActionController
@onready var property_rail: OwnedPropertyRailController = %OwnedPropertyRailController
@onready var building_palette_controller: BuildingPaletteController = %BuildingPaletteController
@onready var gameplay_feedback: GameplayFeedbackController = %GameplayFeedbackController
@onready var turn_camera: TurnCameraController = %TurnCameraController
@onready var card_hand_controller = %CardHandController


func _ready() -> void:
	_configure_participants()
	_configure_presentation()
	game_manager.start_match()
	property_rail.refresh_owned_properties()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().change_scene_to_file("res://play_scenes/main_menu.tscn")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"turn_action") and turn_hud.perform_turn_action():
		get_viewport().set_input_as_handled()


func get_selected_property() -> Plot:
	return property_rail.get_selected_property()


func _configure_participants() -> void:
	var game_session := get_node("/root/GameSession")
	var participant_count := clampi(
		int(game_session.get("participant_count")),
		2,
		GameManager.MAX_PARTICIPANTS
	)
	var configured_participants: Array[Entity] = []
	for index in available_participants.size():
		var participant := available_participants[index]
		var is_participating := index < participant_count
		participant.visible = is_participating
		participant.type = (
			Entity.EntityType.PLAYER
			if index == 0
			else Entity.EntityType.AI
		)
		participant.display_name = "Player 1" if index == 0 else "AI %d" % index
		if is_participating:
			configured_participants.append(participant)
	game_manager.participants = configured_participants


func _configure_presentation() -> void:
	local_hud.configure(local_player, %MoneyLabel, %HealthBar, %HealthLabel)
	turn_hud.configure(
		game_manager,
		local_player,
		%TurnLabel,
		%RollResultLabel,
		%TurnActionButton
	)
	world_actions.configure(
		game_manager,
		game_camera,
		local_player,
		%WorldActionPanel,
		%WorldActionTitle,
		%WorldActionDetails,
		%BuyButton,
		%DeclineButton,
		%PayRentButton
	)
	property_rail.configure(
		game_manager,
		game_camera,
		local_player,
		%OwnedPropertiesRail,
		%OwnedPropertiesList
	)
	property_rail.selection_changed.connect(_on_property_selection_changed)
	building_palette_controller.configure(
		game_manager,
		local_player,
		property_rail,
		%BuildingPalette,
		%BuildingManagerTitle,
		%BuildingTargetLabel,
		%BuildingStatusLabel,
		%BuildingDescriptionLabel,
		$GameUI/BuildingPalette/Margin/Content/Scroll,
		%BuildingButtonList,
		%BankControls,
		%BankBalanceLabel,
		%BankInterestLabel,
		%BankAmount,
		%BankDepositButton,
		%BankWithdrawButton
	)
	gameplay_feedback.configure(game_manager, game_camera)
	turn_camera.configure(game_manager, game_camera)
	card_hand_controller.configure(
		game_manager,
		local_player,
		%CardHand,
		%CardList
	)


func _on_property_selection_changed(
	previous_plot: Plot,
	current_plot: Plot
) -> void:
	property_deed_selection_changed.emit(previous_plot, current_plot)
