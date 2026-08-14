extends Node3D

signal property_deed_selection_changed(previous_plot: Plot, current_plot: Plot)

@onready var game_manager: GameManager = $GameManager
@onready var game_camera: GameCamera = $Camera3D
@onready var game_session := get_node("/root/GameSession")
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
@onready var set_bonus_hud: SetBonusHudController = %SetBonusHudController
@onready var local_seat: LocalSeatController = %LocalSeatController
@onready var developer_tools: DeveloperToolsController = %DeveloperToolsController

var local_human_count := 1


func _ready() -> void:
	_configure_participants()
	_apply_local_settings()
	_configure_presentation()
	game_manager.start_match()
	property_rail.refresh_owned_properties()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().change_scene_to_file("res://play_scenes/main_menu.tscn")
		get_viewport().set_input_as_handled()
		return
	if developer_tools.try_handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"turn_action") and turn_hud.perform_turn_action():
		get_viewport().set_input_as_handled()


func get_selected_property() -> Plot:
	return property_rail.get_selected_property()


func _configure_participants() -> void:
	var participant_count := clampi(
		int(game_session.get("participant_count")),
		2,
		GameManager.MAX_PARTICIPANTS
	)
	local_human_count = clampi(
		int(game_session.get("local_human_count")),
		1,
		participant_count
	)
	var configured_participants: Array[Entity] = []
	var ai_number := 0
	for index in available_participants.size():
		var participant := available_participants[index]
		var is_participating := index < participant_count
		participant.visible = is_participating
		var is_human := index < local_human_count
		participant.type = Entity.EntityType.PLAYER if is_human else Entity.EntityType.AI
		if is_human:
			participant.display_name = "Player %d" % (index + 1)
		else:
			ai_number += 1
			participant.display_name = "AI %d" % ai_number
		if is_participating:
			configured_participants.append(participant)
	game_manager.participants = configured_participants


func _apply_local_settings() -> void:
	if game_camera.settings == null:
		game_camera.settings = CameraSettings.new()
	else:
		game_camera.settings = game_camera.settings.duplicate(true) as CameraSettings
	game_camera.settings.target_mode = (
		CameraSettings.TargetMode.ALL_TURNS
		if bool(game_session.get("camera_follow_all_turns"))
		else CameraSettings.TargetMode.LOCAL_PLAYER_ONLY
	)
	game_camera.settings.dynamic_movement_view = bool(
		game_session.get("dynamic_camera_motion")
	)


func _configure_presentation() -> void:
	local_seat.configure(game_manager)
	local_seat.presented_player_changed.connect(_set_presented_player)
	developer_tools.configure(game_manager, game_session, %DevToastLabel)
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
		game_camera,
		local_player,
		%CardHand,
		%CardList
	)
	set_bonus_hud.configure(
		game_manager,
		local_player,
		%SetBonusSummaryPanel,
		%SetBonusSummaryLabel,
		%GuidedCurrentPanel,
		%GuidedCurrentDetails,
		%GuidedCurrentMinusButton,
		%GuidedCurrentKeepButton,
		%GuidedCurrentPlusButton
	)


func _set_presented_player(player: Entity) -> void:
	if not is_instance_valid(player):
		return
	local_player = player
	game_camera.local_player = player
	local_hud.set_player(player)
	turn_hud.set_local_player(player, local_human_count > 1)
	world_actions.set_local_player(player)
	property_rail.set_local_player(player)
	building_palette_controller.set_local_player(player)
	card_hand_controller.set_local_player(player)
	set_bonus_hud.set_local_player(player)


func _on_property_selection_changed(
	previous_plot: Plot,
	current_plot: Plot
) -> void:
	property_deed_selection_changed.emit(previous_plot, current_plot)
