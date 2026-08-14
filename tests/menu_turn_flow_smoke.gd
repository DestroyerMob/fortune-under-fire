extends SceneTree

const GAME_SCENE := preload("res://play_scenes/test_scene.tscn")
const MENU_SCENE := preload("res://play_scenes/main_menu.tscn")
const IRONWORKS_DATA := preload("res://resources/plots/ironworks.tres")
const APARTMENTS := preload("res://resources/buildings/apartments.tres")
const HOTEL := preload("res://resources/buildings/hotel.tres")
const CASINO := preload("res://resources/buildings/casino.tres")
const BANK := preload("res://resources/buildings/bank.tres")
const GUN_TOWER := preload("res://resources/buildings/gun_tower.tres")
const ARTILLERY := preload("res://resources/buildings/artillery_battery.tres")
const TESLA_COIL := preload("res://resources/buildings/tesla_coil.tres")
const MEDIC_TOWER := preload("res://resources/buildings/medic_tower.tres")
const FOLD_EARLY := preload("res://resources/cards/fold_early.tres")
const OVERTIME := preload("res://resources/cards/overtime.tres")
const EMERGENCY_TRANSFER := preload(
	"res://resources/cards/emergency_transfer.tres"
)
const TACTICS_DECK := preload("res://resources/card_selectors/tactics_deck.tres")
const CARD_PLAY_RESULT_SCRIPT := preload(
	"res://scripts/gameplay/card_play_result.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("local_human_count", 1)
	game_session.set("dev_options_enabled", false)
	game_session.set("camera_follow_all_turns", true)
	game_session.set("dynamic_camera_motion", false)
	_test_turn_action_mapping()
	await _test_menu_navigation()
	await _test_developer_card_shortcut()
	await _test_local_multiplayer()
	await _test_plot_economy()
	await _test_property_sets_and_control_bonuses()
	await _test_building_system()
	await _test_damage_building_defeat_flow()
	await _test_start_income_flow()
	await _test_rent_turn_flow()
	await _test_bank_and_loss_conditions()
	await _test_card_system()
	for participant_count in range(2, 5):
		await _test_participant_count(participant_count)

	if _failures.is_empty():
		print("PASS: menu, cards, buildings, and 2-4 player turn flow")
		quit()
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_turn_action_mapping() -> void:
	_expect(InputMap.has_action(&"turn_action"), "The shared turn action should exist.")
	var has_space_binding := false
	for event in InputMap.action_get_events(&"turn_action"):
		if (
			event is InputEventKey
			and (
				event.physical_keycode == KEY_SPACE
				or event.keycode == KEY_SPACE
			)
		):
			has_space_binding = true
	_expect(has_space_binding, "Space should trigger the shared turn action.")
	_expect(
		InputMap.has_action(&"dev_grant_card"),
		"The developer card shortcut action should exist."
	)
	var has_c_binding := false
	for event in InputMap.action_get_events(&"dev_grant_card"):
		if (
			event is InputEventKey
			and (event.physical_keycode == KEY_C or event.keycode == KEY_C)
		):
			has_c_binding = true
	_expect(has_c_binding, "C should trigger the developer card grant action.")


func _test_menu_navigation() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("dev_options_enabled", true)
	var menu := MENU_SCENE.instantiate()
	root.add_child(menu)
	await process_frame

	var main_panel := menu.get_node("MainPanel") as PanelContainer
	var setup_panel := menu.get_node("PlayerSetupPanel") as PanelContainer
	var settings_panel := menu.get_node("SettingsPanel") as PanelContainer
	_expect(main_panel.visible, "The main menu should be visible on launch.")
	_expect(not setup_panel.visible, "The player setup should be hidden on launch.")
	_expect(not settings_panel.visible, "Settings should be hidden on launch.")

	var settings_button := menu.get_node(
		"MainPanel/Margin/Content/SettingsButton"
	) as Button
	settings_button.pressed.emit()
	_expect(
		settings_panel.visible and not main_panel.visible,
		"Settings should open from the main menu without entering match setup."
	)
	_expect(
		menu.get_node("SettingsPanel/Margin/Content/DevOptionsRow/Margin/Row/DevOptionsCheck").button_pressed
		and menu.get_node("SettingsPanel/Margin/Content/DevShortcutPanel").visible,
		"Enabled developer options should reveal their available shortcut."
	)
	var settings_back := menu.get_node(
		"SettingsPanel/Margin/Content/Footer/SettingsBackButton"
	) as Button
	settings_back.pressed.emit()
	_expect(
		main_panel.visible and not settings_panel.visible,
		"Back should return from settings to the main navigation."
	)

	var new_game_button := menu.get_node(
		"MainPanel/Margin/Content/NewGameButton"
	) as Button
	new_game_button.pressed.emit()
	_expect(not main_panel.visible, "New Game should hide the main menu panel.")
	_expect(setup_panel.visible, "New Game should show the player setup panel.")
	var more_humans := menu.get_node(
		"PlayerSetupPanel/Margin/Content/HumanSeats/MoreHumansButton"
	) as Button
	var seat_summary := menu.get_node(
		"PlayerSetupPanel/Margin/Content/SelectionSummary"
	) as Label
	more_humans.pressed.emit()
	_expect(
		seat_summary.text.contains("2 local humans"),
		"Match setup should allow more than one local human seat."
	)

	menu.queue_free()
	await process_frame
	game_session.set("local_human_count", 1)
	game_session.set("dev_options_enabled", false)


func _test_developer_card_shortcut() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	game_session.set("local_human_count", 1)
	game_session.set("dev_options_enabled", false)
	game_session.set("camera_follow_all_turns", false)
	game_session.set("dynamic_camera_motion", true)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var player := game_screen.get_node("Player") as Entity
	var developer_tools := game_screen.get_node(
		"PresentationSystems/DeveloperToolsController"
	) as DeveloperToolsController
	var game_camera := game_screen.get_node("Camera3D") as GameCamera
	var toast := game_screen.get_node("GameUI/DevToastLabel") as Label
	var initial_cards: int = player.get_total_card_count()
	_expect(
		developer_tools.grant_random_card() == null
		and player.get_total_card_count() == initial_cards,
		"The developer card command should do nothing while dev options are off."
	)
	game_session.set("dev_options_enabled", true)
	var granted_card: CardData = developer_tools.grant_random_card()
	_expect(
		granted_card != null
		and player.get_total_card_count() == initial_cards + 1,
		"The enabled developer shortcut should grant the active human a random card."
	)
	_expect(
		toast.visible and toast.text.contains(granted_card.display_name),
		"A developer grant should give immediate, compact visual confirmation."
	)
	_expect(
		game_camera.settings.target_mode
		== CameraSettings.TargetMode.LOCAL_PLAYER_ONLY
		and game_camera.settings.dynamic_movement_view,
		"Saved camera preferences should be applied when gameplay starts."
	)

	game_screen.queue_free()
	await process_frame
	game_session.set("dev_options_enabled", false)
	game_session.set("camera_follow_all_turns", true)
	game_session.set("dynamic_camera_motion", false)


func _test_local_multiplayer() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 3)
	game_session.set("local_human_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var player_one := game_screen.get_node("Player") as Entity
	var player_two := game_screen.get_node("Player2") as Entity
	var bot := game_screen.get_node("Player3") as Entity
	var money_label := game_screen.get_node(
		"GameUI/PlayerStatusPanel/Margin/Content/MoneyLabel"
	) as Label
	var card_hand := game_screen.get_node("GameUI/CardHand") as Control
	var card_list := game_screen.get_node("GameUI/CardHand/CardList") as HBoxContainer
	game_manager.auto_play_ai = false
	board.movement_units_per_second = 1000.0
	player_one.add_card(FOLD_EARLY)
	player_two.add_card(OVERTIME)
	player_two.set_money(777)
	await process_frame

	_expect(
		player_one.type == Entity.EntityType.PLAYER
		and player_two.type == Entity.EntityType.PLAYER
		and bot.type == Entity.EntityType.AI,
		"A mixed local match should configure the requested human seats before its bots."
	)
	_expect(
		game_screen.local_player == player_one
		and card_hand.visible
		and card_list.has_node("CardFoldEarly"),
		"A multi-human match should immediately present Player 1's controls and hand."
	)

	var fixed_roll: Array[int] = [1, 1]
	await game_manager.play_active_turn(fixed_roll)
	if game_manager.has_pending_landing_action():
		game_manager.request_property_purchase(player_one, false)
	_expect(
		game_manager.request_end_turn(player_one),
		"Player 1 should be able to complete their local turn normally."
	)
	await process_frame
	_expect(
		game_manager.get_active_entity() == player_two
		and game_screen.local_player == player_two
		and game_screen.get_node("GameUI/Actions/TurnActionButton").visible,
		"Ending Player 1's turn should give Player 2 immediate manual control."
	)
	_expect(
		money_label.text.contains("$777")
		and card_hand.visible
		and card_list.has_node("CardOvertime")
		and not card_list.has_node("CardFoldEarly"),
		"HUD and private hand data should switch atomically to Player 2."
	)
	_expect(
		game_screen.get_node("GameUI/TurnStatus/TurnLabel").text.contains("Player 2"),
		"The persistent turn label should make the active local player unambiguous."
	)

	game_screen.queue_free()
	await process_frame
	game_session.set("local_human_count", 1)


func _test_plot_economy() -> void:
	var property_plot := Plot.new()
	var buyer := Entity.new()
	var tenant := Entity.new()
	root.add_child(property_plot)
	root.add_child(buyer)
	root.add_child(tenant)
	await process_frame
	await _finish_plot_economy(property_plot, buyer, tenant)


func _test_property_sets_and_control_bonuses() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var owner := game_screen.get_node("Player") as Entity
	var opponent := game_screen.get_node("Player2") as Entity
	var set_system := game_manager.set_bonus_system
	var guided_panel := game_screen.get_node(
		"GameUI/GuidedCurrentPanel"
	) as PanelContainer
	var set_summary := game_screen.get_node(
		"GameUI/SetBonusSummaryPanel"
	) as PanelContainer
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false
	owner.set_money(10000)
	opponent.set_money(10000)

	_expect(board.plots.size() == 48, "The main board should contain exactly 48 spaces.")
	var expected_route_groups: Array[StringName] = [
		&"ironworks",
		&"verdant_ward",
		&"tidal_bastion",
		&"arcane_reach",
		&"obsidian_crown",
		&"crimson_court",
		&"ember_quarter",
		&"royal_foundry",
	]
	var actual_route_groups: Array[StringName] = []
	var previous_group_id := &""
	var group_plots: Dictionary[StringName, Array] = {}
	var card_count := 0
	var corner_count := 0
	for plot in board.plots:
		if plot.data == null:
			continue
		if plot.data.type == PlotData.PlotType.CARD:
			card_count += 1
			previous_group_id = &""
			continue
		if plot.data.type == PlotData.PlotType.CORNER:
			corner_count += 1
			previous_group_id = &""
			continue
		var group := plot.data.property_group
		if group == null:
			continue
		if not group_plots.has(group.group_id):
			group_plots[group.group_id] = []
		group_plots[group.group_id].append(plot)
		if group.group_id != previous_group_id:
			actual_route_groups.append(group.group_id)
			previous_group_id = group.group_id
	_expect(
		actual_route_groups == expected_route_groups
		and card_count == 4
		and corner_count == 4,
		"The route should be four Corner → five → Card → five sides in design order."
	)
	for group_id in expected_route_groups:
		_expect(
			group_plots.has(group_id) and group_plots[group_id].size() == 5,
			"Every property set should contain five plots: %s." % group_id
		)

	var controlled_groups: Dictionary[StringName, PropertyGroupData] = {}
	for group_id in expected_route_groups:
		var plots: Array = group_plots[group_id]
		var group := (plots[0] as Plot).data.property_group
		controlled_groups[group_id] = group
		_expect(
			not group.control_bonus_name.is_empty()
			and not group.control_bonus_description.is_empty(),
			"Every set should declare its global control power in data: %s." % group_id
		)

	for plot_variant in group_plots[&"ironworks"]:
		(plot_variant as Plot).set_plot_owner(owner)
	await process_frame
	var ironworks := controlled_groups[&"ironworks"]
	_expect(
		set_system.owns_complete_set(owner, ironworks)
		and set_summary.visible,
		"Owning all five Ironworks plots should expose its global set power."
	)
	var discounted_cost := game_manager.get_building_cost(owner, APARTMENTS)
	var first_ironworks_plot := group_plots[&"ironworks"][0] as Plot
	var second_ironworks_plot := group_plots[&"ironworks"][1] as Plot
	var money_before_discounted_build := owner.money
	_expect(
		game_manager.request_construct_building(owner, first_ironworks_plot, APARTMENTS)
		and discounted_cost == 105
		and owner.money == money_before_discounted_build - discounted_cost,
		"Industrial Efficiency should discount the first construction by 25%."
	)
	_expect(
		game_manager.get_building_cost(owner, HOTEL) == HOTEL.build_cost,
		"Industrial Efficiency should be consumed after the first construction."
	)
	# Keep a second valid build target to prove the quote does not alter plots.
	_expect(second_ironworks_plot.building == null, "A price quote should not construct anything.")

	for plot_variant in group_plots[&"verdant_ward"]:
		(plot_variant as Plot).set_plot_owner(owner)
	var verdant := controlled_groups[&"verdant_ward"]
	_expect(
		set_system.get_charges(owner, verdant) == 1
		and set_system.modify_incoming_damage(owner, 20) == 10
		and set_system.get_charges(owner, verdant) == 0,
		"Living Ward should halve one building attack and consume its lap charge."
	)
	board.past_start.emit(owner)
	_expect(
		set_system.get_charges(owner, verdant) == 1,
		"Passing Start should refill Living Ward."
	)

	for plot_variant in group_plots[&"ember_quarter"]:
		(plot_variant as Plot).set_plot_owner(owner)
	var ember := controlled_groups[&"ember_quarter"]
	_expect(
		set_system.modify_outgoing_damage(owner, 20) == 30
		and set_system.get_charges(owner, ember) == 0,
		"Overcharge should empower one attack by 50% and consume its lap charge."
	)

	for plot_variant in group_plots[&"crimson_court"]:
		(plot_variant as Plot).set_plot_owner(owner)
	var crimson_plot := group_plots[&"crimson_court"][0] as Plot
	var rent := crimson_plot.get_rent_value()
	var tribute := int(roundi(float(rent * 20) / 100.0))
	var owner_before_tribute := owner.money
	var opponent_before_tribute := opponent.money
	crimson_plot.pay_rent(opponent)
	_expect(
		owner.money == owner_before_tribute + rent + tribute
		and opponent.money == opponent_before_tribute - rent,
		"Tribute should create 20% extra for the owner without charging the payer."
	)
	owner_before_tribute = owner.money
	crimson_plot.pay_rent(opponent)
	_expect(
		owner.money == owner_before_tribute + rent,
		"Tribute should trigger only once per opponent during the owner's lap."
	)

	for plot_variant in group_plots[&"tidal_bastion"]:
		(plot_variant as Plot).set_plot_owner(owner)
	var rolled_values: Array = [[]]
	game_manager.dice_rolled.connect(
		func(entity: Entity, values: Array[int]) -> void:
			if entity == owner:
				rolled_values[0] = values.duplicate()
	)
	var starting_index := board.get_entity_plot_index(owner)
	_expect(
		game_manager.request_roll(owner)
		and game_manager.has_pending_movement_adjustment()
		and guided_panel.visible
		and not game_manager.request_end_turn(owner),
		"Guided Current should pause a rolled turn for the ±1 choice."
	)
	var expected_destination := posmod(
		starting_index + rolled_values[0][0] + rolled_values[0][1] + 1,
		board.plots.size()
	)
	_expect(
		game_manager.request_movement_adjustment(owner, 1),
		"Guided Current should accept one positive movement adjustment."
	)
	await create_timer(0.25).timeout
	_expect(
		board.get_entity_plot_index(owner) == expected_destination
		and not guided_panel.visible,
		"Guided Current movement should use the adjusted route destination."
	)
	if game_manager.has_pending_purchase():
		game_manager.request_property_purchase(owner, false)
	if game_manager.has_pending_rent():
		game_manager.request_rent_payment(owner)
	_expect(game_manager.request_end_turn(owner), "The adjusted turn should still end normally.")

	for plot_variant in group_plots[&"arcane_reach"]:
		(plot_variant as Plot).set_plot_owner(owner)
	var forecast_seen: Array = [[]]
	game_manager.upcoming_roll_revealed.connect(
		func(entity: Entity, values: Array[int]) -> void:
			if entity == owner:
				forecast_seen[0] = values.duplicate()
	)
	await game_manager.play_active_turn([1, 1])
	if game_manager.has_pending_purchase():
		game_manager.request_property_purchase(opponent, false)
	if game_manager.has_pending_rent():
		game_manager.request_rent_payment(opponent)
	game_manager.request_end_turn(opponent)
	_expect(
		forecast_seen[0].size() == 2
		and game_manager.get_upcoming_roll(owner) == forecast_seen[0],
		"Intelligence Network should reveal and preserve the authoritative next roll."
	)

	for group_id in [&"obsidian_crown", &"royal_foundry"]:
		for plot_variant in group_plots[group_id]:
			(plot_variant as Plot).set_plot_owner(owner)
		var group := controlled_groups[group_id]
		_expect(
			set_system.owns_complete_set(owner, group)
			and set_system.get_charges(owner, group) == 1,
			"%s should expose one lap-scoped integration charge." % group.display_name
		)

	game_screen.queue_free()
	await process_frame


func _finish_plot_economy(
	property_plot: Plot,
	buyer: Entity,
	tenant: Entity
) -> void:
	property_plot.data = IRONWORKS_DATA
	property_plot.base_rent = 12
	property_plot.tower_rent = 30
	property_plot.buy_price = 100
	buyer.set_money(200)
	tenant.set_money(50)

	var offer_received := [false]
	property_plot.purchase_offered.connect(
		func(offered_to: Entity) -> void:
			offer_received[0] = offered_to == buyer
	)
	property_plot.on_land(buyer)
	_expect(offer_received[0], "An unowned property should offer itself to the landing entity.")
	_expect(property_plot.purchase(buyer), "An entity with enough money should buy a property.")
	_expect(property_plot.plot_owner == buyer, "A purchased property should record its owner.")
	_expect(buyer.money == 100, "A property purchase should deduct its buy price.")
	property_plot.set_has_tower(true)
	_expect(property_plot.get_base_rent() == 12, "A tower should not change Start income.")
	_expect(property_plot.get_rent_value() == 30, "A tower should activate modified rent.")

	var rent_offer_received := [false]
	property_plot.rent_due.connect(
		func(payer: Entity, owner: Entity, amount: int) -> void:
			rent_offer_received[0] = payer == tenant and owner == buyer and amount == 30
	)
	property_plot.on_land(tenant)
	_expect(rent_offer_received[0], "An owned property should request rent from a trespasser.")
	_expect(tenant.money == 50, "Rent should wait for the payer to confirm it.")
	_expect(property_plot.pay_rent(tenant) == 30, "Confirming rent should return tower rent.")
	_expect(tenant.money == 20, "Confirmed rent should deduct the modified tower value.")
	_expect(buyer.money == 130, "Confirmed tower rent should transfer to the plot owner.")
	tenant.set_money(5)
	_expect(not tenant.is_defeated(), "A player with non-negative carried cash should remain alive.")
	_expect(
		property_plot.pay_rent(tenant) == 30,
		"A mandatory rent obligation should be paid in full even when cash is short."
	)
	_expect(
		tenant.money == -25
		and tenant.get_defeat_reason() == Entity.DefeatReason.DEBT,
		"Crossing below zero carried cash should eliminate the payer for debt."
	)
	_expect(buyer.money == 160, "Debt rent should still reach the property's owner in full.")

	property_plot.queue_free()
	buyer.queue_free()
	tenant.queue_free()
	await process_frame


func _test_building_system() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var owner := game_screen.get_node("Player") as Entity
	var opponent := game_screen.get_node("Player2") as Entity
	var building_palette := game_screen.get_node(
		"GameUI/BuildingPalette"
	) as PanelContainer
	var building_button_list := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/Scroll/BuildingButtonList"
	) as VBoxContainer
	var building_status_label := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BuildingStatusLabel"
	) as Label
	var money_label := game_screen.get_node(
		"GameUI/PlayerStatusPanel/Margin/Content/MoneyLabel"
	) as Label
	var deed_list := game_screen.get_node(
		"GameUI/OwnedPropertiesRail/Scroll/OwnedPropertiesList"
	) as VBoxContainer
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false
	owner.set_money(5000)
	for participant in game_manager.participants:
		var world_health := participant.get_health_indicator()
		_expect(
			is_instance_valid(world_health)
			and world_health.position.y > 0.0
			and world_health.has_node("Background")
			and world_health.has_node("Fill"),
			"Every participant should show live health above their world piece."
		)
	_expect(
		not CASINO.get_effect_summary().contains("d6")
		and not CASINO.description.contains("d6"),
		"Player-facing Casino text should explain its 1–6 roll without dice shorthand."
	)

	var sites := _get_first_ownable_plots(board, 7)
	_expect(sites.size() == 7, "The building test requires seven ownable plots.")
	if sites.size() < 7:
		game_screen.queue_free()
		await process_frame
		return
	for plot in sites:
		plot.set_plot_owner(owner)

	_expect(
		game_manager.available_buildings.size() == 8,
		"The build palette should expose the initial buildings, Medic Tower, and Bank."
	)
	_expect(not building_palette.visible, "The building palette should wait for a selected deed.")
	var first_deed := _get_property_deed(deed_list, 0)
	first_deed.button_pressed = true
	first_deed.pressed.emit()
	_expect(building_palette.visible, "Selecting an owned deed should reveal the build palette.")
	_expect(
		building_button_list.get_child_count() == 8,
		"The right-side palette should contain all eight available buildings."
	)
	_expect(
		building_button_list.has_node("BuildMedicTowerButton"),
		"Medic Tower should be available from the construction palette."
	)
	_expect(
		building_button_list.has_node("BuildBankButton"),
		"Bank should be available from the construction palette."
	)
	var apartments_button := building_button_list.get_node(
		"BuildApartmentsButton"
	) as Button
	var money_before_build := owner.money
	var expected_build_cost := game_manager.get_building_cost(owner, APARTMENTS)
	apartments_button.pressed.emit()
	_expect(sites[0].building == APARTMENTS, "Apartments should construct on the selected deed.")
	_expect(
		owner.money == money_before_build - expected_build_cost
		and expected_build_cost < APARTMENTS.build_cost,
		"Complete Ironworks control should discount the first construction each turn."
	)
	_expect(
		building_status_label.text.contains("Apartments"),
		"The palette should identify the building installed on the selected site."
	)
	_expect(
		building_palette.visible,
		"After construction, the contextual panel should remain as a plot manager."
	)
	_expect(
		not building_button_list.get_parent().visible,
		"A built plot manager should replace construction choices with building details."
	)
	_expect(
		(sites[0].get_node("Tower") as MeshInstance3D).visible,
		"A constructed building should have an in-world visual."
	)
	_expect(
		not game_manager.request_construct_building(owner, sites[0], HOTEL),
		"A plot should accept only one building."
	)

	# Install the remaining economy types and verify predictable, landing, and
	# random income independently.
	sites[1].set_building(HOTEL)
	sites[2].set_building(CASINO)
	var base_income := board.get_owned_property_income(owner)
	var casino_payout := [0]
	var casino_roll := [0]
	var typed_casino_activation: Array[BuildingActivation] = []
	board.building_effect_resolved.connect(
		func(activation: BuildingActivation) -> void:
			if activation.building == CASINO:
				typed_casino_activation.append(activation)
	)
	board.building_activated.connect(
		func(
			activated_owner: Entity,
			_source_plot: Plot,
			building: BuildingData,
			_target: Entity,
			money_amount: int,
			_damage_amount: int,
			_healing_amount: int,
			die_roll: int
		) -> void:
			if activated_owner == owner and building == CASINO:
				casino_payout[0] = money_amount
				casino_roll[0] = die_roll
	)
	var money_before_lap := owner.money
	var lap_income := board.award_start_income(owner)
	_expect(
		casino_roll[0] >= 1 and casino_roll[0] <= 6,
		"A Casino lap activation should roll one six-sided die."
	)
	_expect(
		casino_payout[0] == CASINO.money_value * casino_roll[0],
		"Casino income should scale with its activation roll."
	)
	_expect(
		typed_casino_activation.size() == 1
		and typed_casino_activation[0].kind
			== BuildingActivation.EffectKind.LAP_INCOME
		and typed_casino_activation[0].amount == casino_payout[0],
		"Building effects should publish one typed activation result."
	)
	_expect(
		lap_income == base_income + APARTMENTS.money_value + casino_payout[0],
		"Lap income should combine property income, Apartments, and Casino payout."
	)
	_expect(owner.money == money_before_lap + lap_income, "Lap income should reach the owner.")
	_expect(
		owner.has_active_feedback_kind(&"money"),
		"Completing a profitable lap should animate its money above the owner."
	)
	var hotel_rent := sites[1].get_tower_rent()
	var owner_before_hotel := owner.money
	var opponent_before_hotel := opponent.money
	_expect(
		sites[1].pay_rent(opponent) == hotel_rent,
		"A Hotel should charge its property's configured tower rent."
	)
	_expect(
		owner.money == owner_before_hotel + hotel_rent
		and opponent.money == opponent_before_hotel - hotel_rent,
		"Hotel landing income should transfer from the opponent to its owner."
	)
	_expect(
		money_label.text.contains("+$%d" % hotel_rent),
		"Local rent income should pulse as an inline Funds delta even off-camera."
	)
	_expect(
		owner.has_active_feedback_kind(&"money")
		and opponent.has_active_feedback_kind(&"money"),
		"Rent should animate both the owner's gain and the payer's loss."
	)
	var money_feedback := _get_feedback_label(owner, &"money")
	_expect(
		is_instance_valid(money_feedback)
		and not money_feedback.fixed_size
		and money_feedback.font_size <= 26
		and not money_feedback.text.contains("RENT")
		and not money_feedback.text.contains("LAP"),
		"Money feedback should be a compact amount without event-description text."
	)

	# Damage buildings deliberately exercise three different trigger shapes.
	sites[3].set_building(GUN_TOWER)
	opponent.set_health(opponent.max_health)
	await _move_entity_to_plot(board, opponent, sites[3])
	_expect(
		opponent.health == opponent.max_health - GUN_TOWER.damage,
		"A Gun Tower should deal reliable damage on its own plot."
	)
	_expect(
		opponent.has_active_feedback_kind(&"damage"),
		"Building attacks should animate damage above their target."
	)
	_expect(
		is_equal_approx(
			opponent.get_health_indicator_ratio(),
			float(opponent.health) / float(opponent.max_health)
		),
		"World health indicators should update immediately after damage."
	)
	var opponent_health_fill := opponent.get_health_indicator().get_node(
		"Fill"
	) as MeshInstance3D
	_expect(
		is_equal_approx(
			opponent_health_fill.scale.x,
			opponent.get_health_indicator_ratio()
		),
		"The world health bar fill should shrink to the entity's health ratio."
	)
	var damage_feedback := _get_feedback_label(opponent, &"damage")
	_expect(
		is_instance_valid(damage_feedback)
		and not damage_feedback.fixed_size
		and damage_feedback.font_size <= 26
		and not damage_feedback.text.contains("HP"),
		"Damage feedback should be a compact world-space amount, not billboard text."
	)
	_expect(
		(sites[3].get_node("Tower") as MeshInstance3D).has_meta(&"activation_tween"),
		"An attacking building should play its activation pulse."
	)
	sites[3].clear_building()
	sites[3].set_building(MEDIC_TOWER)
	_expect(
		sites[3].get_rent_value() == 0
		and not sites[3].can_collect_rent_from(opponent),
		"Medic Tower should sacrifice all rent from its plot."
	)
	owner.set_health(55)
	await _move_entity_to_plot(board, owner, sites[3])
	_expect(
		owner.health == 55 + MEDIC_TOWER.healing,
		"Medic Tower should heal its owner by its configured amount on landing."
	)
	_expect(
		owner.has_active_feedback_kind(&"healing"),
		"Medic Tower healing should use compact world-space feedback."
	)
	var opponent_health_before_medic := opponent.health
	await _move_entity_to_plot(board, opponent, sites[3])
	_expect(
		opponent.health == opponent_health_before_medic,
		"Medic Tower should not heal or damage an opponent who lands on it."
	)
	sites[3].clear_building()
	sites[4].set_building(ARTILLERY)
	opponent.set_health(opponent.max_health)
	await _move_entity_to_plot(board, opponent, sites[0])
	_expect(
		opponent.health == opponent.max_health - ARTILLERY.damage,
		"Artillery should support a nearby property belonging to its owner."
	)
	sites[4].clear_building()
	sites[5].set_building(TESLA_COIL)
	sites[6].set_building(TESLA_COIL)
	opponent.set_health(opponent.max_health)
	await _move_entity_to_plot(board, opponent, sites[5])
	_expect(
		opponent.health == opponent.max_health - TESLA_COIL.damage * 2,
		"A Tesla Coil should scale damage through its connected coil network."
	)

	game_screen.queue_free()
	await process_frame


func _test_damage_building_defeat_flow() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 3)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var local_player := game_screen.get_node("Player") as Entity
	var opponent := game_screen.get_node("Player2") as Entity
	var game_camera := game_screen.get_node("Camera3D") as GameCamera
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false
	var destination := board.get_plot(2)
	destination.set_plot_owner(opponent)
	destination.set_building(GUN_TOWER)
	local_player.set_health(GUN_TOWER.damage)
	var fixed_roll: Array[int] = [1, 1]
	await game_manager.play_active_turn(fixed_roll)
	_expect(local_player.is_defeated(), "Lethal building damage should defeat the mover.")
	_expect(
		local_player.get_defeat_reason() == Entity.DefeatReason.HEALTH,
		"Reaching zero health should record health depletion as the loss condition."
	)
	_expect(
		game_manager.get_active_entity() == opponent,
		"A building defeat should advance past the defeated mover after movement."
	)
	_expect(
		game_camera.target == local_player and game_camera.is_holding_event_target(),
		"Lethal building damage should keep the camera on its target while it resolves."
	)
	_expect(
		not game_manager.has_pending_landing_action(),
		"A building defeat should clear unresolved landing payments."
	)
	await create_timer(1.1).timeout
	_expect(
		game_camera.target == opponent and not game_camera.is_holding_event_target(),
		"After damage feedback, the camera should continue to the next active entity."
	)

	game_screen.queue_free()
	await process_frame


func _test_start_income_flow() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var local_player := game_screen.get_node("Player") as Entity
	var game_camera := game_screen.get_node("Camera3D") as GameCamera
	var owned_properties_list := game_screen.get_node(
		"GameUI/OwnedPropertiesRail/Scroll/OwnedPropertiesList"
	) as VBoxContainer
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false

	var start_plot := board.get_plot(0)
	var ordinary_corner := board.get_node("Corners/SouthWest") as Plot
	_expect(start_plot.data.display_name == "Start", "The first route plot should be Start.")
	_expect(
		start_plot.data.get_top_color() != ordinary_corner.data.get_top_color(),
		"Start should have a distinct board colour."
	)
	var card_plots: Array[Plot] = []
	for plot in board.plots:
		if plot.data != null and plot.data.type == PlotData.PlotType.CARD:
			card_plots.append(plot)
	_expect(not card_plots.is_empty(), "The board should contain card plots.")
	if not card_plots.is_empty():
		var card_color := card_plots[0].data.get_top_color()
		for card_plot in card_plots:
			_expect(
				card_plot.data.get_top_color().is_equal_approx(card_color),
				"All card plots should share their distinctive card colour."
			)
		for plot in board.plots:
			if plot.data != null and plot.data.is_ownable():
				_expect(
					_color_distance(card_color, plot.data.get_top_color()) > 0.2,
					"Card plots should remain distinct from every property group."
				)
		var card_top := card_plots[0].get_node("Top") as MeshInstance3D
		var card_material := card_top.material_override as StandardMaterial3D
		_expect(
			card_material != null
			and card_material.albedo_color.is_equal_approx(card_color),
			"A card plot should render its configured distinctive colour."
		)

	var first_property := board.get_plot(1)
	var second_property := board.get_plot(2)
	first_property.set_plot_owner(local_player)
	second_property.set_plot_owner(local_player)
	first_property.set_has_tower(true)
	var first_property_deed := _get_property_deed(owned_properties_list, 0)
	var second_property_deed := _get_property_deed(owned_properties_list, 1)
	first_property_deed.mouse_entered.emit()
	await create_timer(0.1).timeout
	first_property_deed.pressed.emit()
	first_property_deed.mouse_exited.emit()
	second_property_deed.mouse_entered.emit()
	await create_timer(0.1).timeout
	_expect(
		game_camera.target == second_property,
		"Moving directly between deeds should not snap the camera back in between."
	)
	second_property_deed.mouse_exited.emit()
	await create_timer(0.1).timeout
	_expect(
		game_camera.target == first_property,
		"Leaving another deed should restore the selected property's anchor."
	)
	second_property_deed.pressed.emit()
	_expect(
		not first_property_deed.button_pressed and second_property_deed.button_pressed,
		"Selecting another deed should replace the previous selection."
	)
	var movement_blocked_preview := [false]
	board.movement_started.connect(
		func(_entity: Entity, _spaces: int, _destination_index: int) -> void:
			first_property_deed.mouse_entered.emit()
			movement_blocked_preview[0] = game_camera.target == local_player
	)
	var expected_income := (
		first_property.get_base_rent()
		+ second_property.get_base_rent()
	)
	var money_before_start := local_player.money
	var awarded_income := [-1]
	game_manager.start_income_awarded.connect(
		func(entity: Entity, amount: int) -> void:
			if entity == local_player:
				awarded_income[0] = amount
	)
	board.register_entity(local_player, board.plots.size() - 1)
	var wrap_roll: Array[int] = [1, 1]
	await game_manager.play_active_turn(wrap_roll)
	_expect(
		movement_blocked_preview[0],
		"A deed hover should not take camera focus while a player is moving."
	)
	_expect(
		awarded_income[0] == expected_income,
		"Passing Start should award the sum of owned properties' base rents."
	)
	_expect(
		local_player.money == money_before_start + expected_income,
		"Passing Start income should be added to the entity's balance."
	)
	_expect(
		expected_income < first_property.get_tower_rent() + second_property.get_base_rent(),
		"Tower rent should not inflate income generated at Start."
	)

	game_screen.queue_free()
	await process_frame


func _test_rent_turn_flow() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var local_player := game_screen.get_node("Player") as Entity
	var other_player := game_screen.get_node("Player2") as Entity
	var game_camera := game_screen.get_node("Camera3D") as GameCamera
	var fixed_roll: Array[int] = [1, 1]
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false

	await game_manager.play_active_turn(fixed_roll)
	var target_plot := game_manager.get_pending_purchase_plot()
	_expect(is_instance_valid(target_plot), "The rent scenario requires an ownable destination.")
	_expect(
		game_manager.request_turn_action(local_player),
		"End Turn should dismiss an unanswered property offer."
	)
	_expect(
		not is_instance_valid(target_plot.plot_owner),
		"Ignoring a purchase offer should leave its property unowned."
	)

	board.register_entity(other_player, 0)
	await game_manager.play_active_turn(fixed_roll)
	_expect(
		game_manager.get_pending_purchase_plot() == target_plot,
		"The second player should receive an offer for the same property."
	)
	var owner_money_before_purchase := other_player.money
	var purchase_price := target_plot.get_buy_price()
	_expect(
		game_manager.request_property_purchase(other_player, true),
		"The second player should be able to buy the target property."
	)
	_expect(
		other_player.money == owner_money_before_purchase - purchase_price,
		"The owner should pay the target property's buy price."
	)
	target_plot.set_has_tower(true)
	var tower_mesh := target_plot.get_node("Tower") as MeshInstance3D
	_expect(tower_mesh.visible, "A towered property should show its tower in-world.")
	var owner_marker := target_plot.get_node("OwnerMarker") as Node3D
	var owner_label := target_plot.get_node("OwnerMarker/OwnerLabel") as Label3D
	var owner_flag := target_plot.get_node("OwnerMarker/Flag") as MeshInstance3D
	_expect(owner_marker.visible, "A purchased property should show its ownership marker.")
	_expect(
		owner_label.text.contains(other_player.get_display_name()),
		"The ownership marker should name the property's owner."
	)
	var owner_flag_material := owner_flag.material_override as StandardMaterial3D
	_expect(
		owner_flag_material != null
		and owner_flag_material.albedo_color.is_equal_approx(other_player.color),
		"The ownership flag should use its owner's entity colour."
	)
	_expect(game_manager.request_turn_action(other_player), "The owner's turn should end.")

	board.register_entity(local_player, 0)
	var payer_money_before_rent := local_player.money
	var owner_money_before_rent := other_player.money
	await game_manager.play_active_turn(fixed_roll)
	_expect(
		game_manager.get_pending_rent_plot() == target_plot,
		"Landing on another entity's property should require rent payment."
	)
	var world_action_panel := game_screen.get_node("GameUI/WorldActionPanel") as PanelContainer
	var world_action_details := game_screen.get_node(
		"GameUI/WorldActionPanel/Margin/Content/WorldActionDetails"
	) as Label
	var pay_rent_button := game_screen.get_node(
		"GameUI/WorldActionPanel/Margin/Content/Buttons/PayRentButton"
	) as Button
	var turn_action_button := game_screen.get_node(
		"GameUI/Actions/TurnActionButton"
	) as Button
	_expect(world_action_panel.visible, "Rent should use the plot's world action menu.")
	_expect(pay_rent_button.visible, "The world action menu should expose Pay Rent.")
	_expect(
		world_action_details.text.contains(other_player.get_display_name())
		and world_action_details.text.contains("Rent due $%d" % target_plot.get_rent_value()),
		"The rent menu should identify the owner and full amount due."
	)
	_expect(
		pay_rent_button.text == "Pay  $%d" % target_plot.get_rent_value(),
		"The rent action should show the full amount owed."
	)
	_expect(not turn_action_button.disabled, "Pending rent should not disable End Turn.")
	_expect(turn_action_button.text == "End Turn", "The shared action should offer End Turn.")
	var expected_rent := target_plot.get_rent_value()
	_expect(
		game_manager.request_turn_action(local_player),
		"End Turn should settle pending rent and advance normally."
	)
	_expect(
		local_player.money == payer_money_before_rent - expected_rent,
		"Confirmed rent should be deducted from the payer."
	)
	_expect(
		other_player.money == owner_money_before_rent + expected_rent,
		"Confirmed rent should be transferred to the owner."
	)
	_expect(
		game_camera.target == local_player and game_camera.is_holding_event_target(),
		"Paying rent should hold the camera on the payer even as the turn advances."
	)
	await create_timer(1.1).timeout
	_expect(
		game_camera.target == other_player and not game_camera.is_holding_event_target(),
		"After rent feedback, the camera should continue to the next active entity."
	)

	game_screen.queue_free()
	await process_frame


func _test_bank_and_loss_conditions() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var owner := game_screen.get_node("Player") as Entity
	var opponent := game_screen.get_node("Player2") as Entity
	var manager_panel := game_screen.get_node("GameUI/BuildingPalette") as PanelContainer
	var manager_title := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BuildingManagerTitle"
	) as Label
	var building_scroll := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/Scroll"
	) as ScrollContainer
	var bank_controls := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BankControls"
	) as VBoxContainer
	var bank_balance_label := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BankControls/BankBalanceLabel"
	) as Label
	var bank_amount := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BankControls/Amount/BankAmount"
	) as SpinBox
	var deposit_button := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BankControls/Buttons/BankDepositButton"
	) as Button
	var withdraw_button := game_screen.get_node(
		"GameUI/BuildingPalette/Margin/Content/BankControls/Buttons/BankWithdrawButton"
	) as Button
	var deed_list := game_screen.get_node(
		"GameUI/OwnedPropertiesRail/Scroll/OwnedPropertiesList"
	) as VBoxContainer
	var roll_result_label := game_screen.get_node("GameUI/RollResultLabel") as Label
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false

	var bank_plot := _get_first_ownable_plots(board, 1)[0]
	bank_plot.set_plot_owner(owner)
	bank_plot.set_building(BANK)
	var bank_deed := _get_property_deed(deed_list, 0)
	bank_deed.button_pressed = true
	bank_deed.pressed.emit()
	await process_frame
	_expect(
		manager_panel.visible
		and manager_title.text == "MANAGE"
		and not building_scroll.visible
		and bank_controls.visible,
		"Selecting a built Bank should turn the build palette into its management view."
	)
	_expect(
		manager_panel.size.y <= 320.0,
		"A built plot manager should collapse to its useful content instead of filling the edge."
	)
	_expect(
		bank_balance_label.text.contains("$0")
		and bank_deed.text.contains("$0 stored"),
		"The Bank manager and deed should both expose the stored balance."
	)
	var bank_deed_status := bank_deed.get_node(
		"FaceMargin/Rows/IdentityRow/SiteStatus"
	) as Label
	_expect(
		bank_deed_status.text.contains("BANK")
		and bank_deed_status.text.contains("$0")
		and bank_deed_status.size.x >= 100.0,
		"A Bank deed should reserve visible space for its compact stored balance."
	)

	var carried_before_deposit := owner.money
	bank_amount.value = 200.0
	deposit_button.pressed.emit()
	_expect(
		owner.money == carried_before_deposit - 200
		and bank_plot.get_bank_balance() == 200,
		"Depositing should move carried cash into the selected Bank."
	)
	bank_amount.value = 50.0
	withdraw_button.pressed.emit()
	_expect(
		owner.money == carried_before_deposit - 150
		and bank_plot.get_bank_balance() == 150,
		"Withdrawing should move stored money back into carried cash."
	)

	var interest_events: Array[int] = []
	game_manager.bank_interest_credited.connect(
		func(credited_owner: Entity, plot: Plot, amount: int, balance: int) -> void:
			if credited_owner == owner and plot == bank_plot:
				interest_events.append(amount)
				_expect(balance == 165, "Bank interest should publish the resulting balance.")
	)
	var carried_before_lap := owner.money
	var expected_property_income := board.get_owned_property_income(owner)
	var lap_income := board.award_start_income(owner)
	_expect(
		lap_income == expected_property_income
		and owner.money == carried_before_lap + expected_property_income,
		"Bank interest should not be mixed into the player's carried lap income."
	)
	_expect(
		bank_plot.get_bank_balance() == 165
		and interest_events == [15]
		and bank_balance_label.text.contains("$165")
		and bank_balance_label.text.contains("+$15")
		and bank_deed.text.contains("$165 stored"),
		"A Bank should credit interest and show its compact stored-balance gain."
	)

	owner.set_money(0)
	_expect(not owner.is_defeated(), "Exactly zero carried cash should be safe.")
	var fixed_roll: Array[int] = [1, 1]
	await game_manager.play_active_turn(fixed_roll)
	if game_manager.has_pending_purchase():
		game_manager.request_property_purchase(owner, false)
	_expect(game_manager.request_end_turn(owner), "The Bank owner should be able to finish the turn.")
	_expect(
		not game_manager.request_bank_deposit(owner, bank_plot, 1)
		and not manager_panel.visible,
		"Bank transactions and its manager should be unavailable outside the owner's turn."
	)

	var winner: Array[Entity] = []
	game_manager.match_finished.connect(
		func(match_winner: Entity) -> void:
			winner.append(match_winner)
	)
	owner.set_money(-1)
	await process_frame
	await process_frame
	_expect(
		owner.is_defeated()
		and owner.get_defeat_reason() == Entity.DefeatReason.DEBT,
		"Negative carried cash should cause debt defeat even when the Bank holds money."
	)
	_expect(
		bank_plot.get_bank_balance() == 165,
		"Banked money should remain separate and must not automatically cover carried debt."
	)
	_expect(
		winner == [opponent]
		and game_manager.state == GameManager.MatchState.FINISHED
		and roll_result_label.text.contains("You lose")
		and roll_result_label.text.contains("In debt"),
		"The final surviving participant should win and the defeated player should see why."
	)

	game_screen.queue_free()
	await process_frame


func _test_card_system() -> void:
	_expect(
		TACTICS_DECK.deck.size() == 3
		and TACTICS_DECK.deck.has(FOLD_EARLY)
		and TACTICS_DECK.deck.has(OVERTIME)
		and TACTICS_DECK.deck.has(EMERGENCY_TRANSFER),
		"The first playable deck should draw the three implemented cards."
	)
	await _test_card_hand_and_additional_roll()
	await _test_end_without_rolling_card()
	await _test_hospital_travel_card()
	await _test_card_target_validation()


func _test_card_hand_and_additional_roll() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var player := game_screen.get_node("Player") as Entity
	var card_hand := game_screen.get_node("GameUI/CardHand") as Control
	var card_list := game_screen.get_node("GameUI/CardHand/CardList") as HBoxContainer
	var card_controller = game_screen.get_node(
		"PresentationSystems/CardHandController"
	)
	var turn_action_button := game_screen.get_node(
		"GameUI/Actions/TurnActionButton"
	) as Button
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false

	player.add_card(FOLD_EARLY)
	player.add_card(OVERTIME)
	player.add_card(EMERGENCY_TRANSFER)
	await create_timer(0.3).timeout
	_expect(card_hand.visible, "A non-empty local hand should appear at the bottom.")
	_expect(card_list.get_child_count() == 3, "The hand should show one card per card type.")
	_expect(
		card_list.position.y >= 200.0,
		"The resting hand should leave only a small card edge above the bottom of the screen."
	)
	var fold_button := card_list.get_node("CardFoldEarly") as Button
	var overtime_button := card_list.get_node("CardOvertime") as Button
	var hospital_button := card_list.get_node("CardEmergencyTransfer") as Button
	_expect(
		not fold_button.disabled
		and not overtime_button.disabled
		and not hospital_button.disabled,
		"Held cards should stay draggable even when their effect would currently be rejected."
	)
	_expect(
		fold_button.tooltip_text.is_empty()
		and overtime_button.tooltip_text.is_empty()
		and hospital_button.tooltip_text.is_empty(),
		"Card rules should be printed on the cards instead of hidden in tooltips."
	)
	var fold_style := fold_button.get_theme_stylebox("normal") as StyleBoxFlat
	var overtime_style := overtime_button.get_theme_stylebox("normal") as StyleBoxFlat
	var hospital_style := hospital_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		fold_style != null
		and fold_style.corner_radius_top_left >= 10
		and overtime_style != null
		and hospital_style != null,
		"Hand cards should retain a rounded, colour-framed physical card silhouette."
	)
	_expect(
		fold_button.size.y > fold_button.size.x
		and is_equal_approx(fold_button.size.y, 238.0)
		and fold_button.clip_contents
		and fold_button.has_node("FaceMargin/CardFace/Header/QuantityBadge")
		and fold_button.has_node("FaceMargin/CardFace/ArtPanel")
		and fold_button.has_node("FaceMargin/CardFace/RuleLabel")
		and fold_button.has_node("FaceMargin/CardFace/Footer/StatusLabel"),
		"Each hand entry should keep a clipped, fixed-size portrait card face."
	)
	var fold_accent := fold_button.get_node("AccentEdge") as PanelContainer
	_expect(
		fold_accent.position.x >= 4.0
		and fold_accent.size.x <= fold_button.size.x - 8.0,
		"A card's top accent should remain inset from its rounded outer border."
	)
	var fold_status := fold_button.get_node(
		"FaceMargin/CardFace/Footer/StatusLabel"
	) as Label
	var overtime_status := overtime_button.get_node(
		"FaceMargin/CardFace/Footer/StatusLabel"
	) as Label
	var hospital_status := hospital_button.get_node(
		"FaceMargin/CardFace/Footer/StatusLabel"
	) as Label
	_expect(
		fold_status.text == "DRAG TO PLAY"
		and overtime_status.text == "DRAG TO PLAY"
		and hospital_status.text == "DRAG TO PLAY",
		"Card faces should invite an activation attempt instead of pre-judging legality."
	)
	_expect(
		not game_screen.has_node("GameUI/CardDropOverlay"),
		"Dragging cards should not create a visible card-goes-here overlay."
	)
	_expect(
		not fold_style.bg_color.is_equal_approx(overtime_style.bg_color)
		and not overtime_style.bg_color.is_equal_approx(hospital_style.bg_color),
		"Each card data resource should provide a distinct colour."
	)
	var resting_y := fold_button.position.y
	fold_button.mouse_entered.emit()
	await create_timer(0.24).timeout
	_expect(
		card_controller.is_hand_revealed()
		and card_list.position.y < 20.0
		and fold_button.position.y < resting_y - 15.0
		and fold_button.scale.x > 1.04
		and fold_status.text == "DRAG TO PLAY",
		"Hovering a card edge should reveal the hand and lift the focused card."
	)
	fold_button.mouse_exited.emit()
	await create_timer(0.4).timeout
	_expect(
		absf(fold_button.position.y - resting_y) < 1.0
		and fold_status.text == "DRAG TO PLAY"
		and not card_controller.is_hand_revealed(),
		"Leaving the hand should return its cards below the screen."
	)
	await _drag_card_to_self(overtime_button, card_controller)
	_expect(
		player.get_card_quantity(OVERTIME) == 1
		and game_manager.get_active_entity() == player
		and not game_manager.has_active_entity_rolled(),
		"An early Overtime attempt should return to the hand without consuming or activating."
	)

	var fixed_roll: Array[int] = [1, 1]
	await game_manager.play_active_turn(fixed_roll)
	if game_manager.has_pending_purchase():
		game_manager.request_property_purchase(player, false)
	await _drag_card_to_self(overtime_button, card_controller)
	_expect(
		player.get_card_quantity(OVERTIME) == 0,
		"Playing a card through the hand UI should consume one copy."
	)
	_expect(
		game_manager.has_roll_available()
		and turn_action_button.text == "Roll Again",
		"Overtime should grant another use of the shared roll action."
	)
	await game_manager.play_active_turn(fixed_roll)
	if game_manager.has_pending_purchase():
		game_manager.request_property_purchase(player, false)
	_expect(
		not game_manager.has_roll_available()
		and turn_action_button.text == "End Turn",
		"After the additional roll, the shared action should return to End Turn."
	)

	game_screen.queue_free()
	await process_frame


func _test_end_without_rolling_card() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var player := game_screen.get_node("Player") as Entity
	var card_hand := game_screen.get_node("GameUI/CardHand") as Control
	var card_list := game_screen.get_node("GameUI/CardHand/CardList") as HBoxContainer
	var card_controller = game_screen.get_node(
		"PresentationSystems/CardHandController"
	)
	game_manager.auto_play_ai = false
	var dice_roll_count := [0]
	game_manager.dice_rolled.connect(
		func(_entity: Entity, _dice_values: Array[int]) -> void:
			dice_roll_count[0] += 1
	)
	var resolved_results: Array = []
	game_manager.card_played.connect(
		func(result) -> void:
			resolved_results.append(result)
	)

	player.add_card(FOLD_EARLY)
	var fold_button := card_list.get_node("CardFoldEarly") as Button
	fold_button.pressed.emit()
	await process_frame
	_expect(
		player.get_card_quantity(FOLD_EARLY) == 1,
		"Clicking a card should not play it without a completed drag."
	)
	_simulate_card_drag(fold_button, Vector2(5.0, 5.0))
	await create_timer(0.35).timeout
	_expect(
		player.get_card_quantity(FOLD_EARLY) == 1
		and game_manager.get_active_entity() == player,
		"Releasing outside the self-cast zone should return the card without consuming it."
	)
	await _drag_card_to_self(fold_button, card_controller)
	_expect(dice_roll_count[0] == 0, "Fold Early should not fabricate a dice roll.")
	_expect(
		game_manager.get_active_entity() != player
		and player.get_card_quantity(FOLD_EARLY) == 0,
		"Fold Early should consume itself and advance the unrolled turn."
	)
	_expect(
		resolved_results.size() == 1
		and resolved_results[0].outcome
			== CARD_PLAY_RESULT_SCRIPT.Outcome.TURN_ENDED,
		"Card play should publish a typed early-turn result."
	)
	_expect(not card_hand.visible, "An empty hand should leave no persistent bottom panel.")

	game_screen.queue_free()
	await process_frame


func _test_hospital_travel_card() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame

	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var player := game_screen.get_node("Player") as Entity
	var card_list := game_screen.get_node("GameUI/CardHand/CardList") as HBoxContainer
	var card_controller = game_screen.get_node(
		"PresentationSystems/CardHandController"
	)
	var turn_action_button := game_screen.get_node(
		"GameUI/Actions/TurnActionButton"
	) as Button
	board.movement_units_per_second = 1000.0
	game_manager.auto_play_ai = false
	player.add_card(EMERGENCY_TRANSFER, 2)
	var hospital_card := card_list.get_node("CardEmergencyTransfer") as Button
	var hospital_status := hospital_card.get_node(
		"FaceMargin/CardFace/Footer/StatusLabel"
	) as Label
	_expect(
		not game_manager.can_play_card(player, EMERGENCY_TRANSFER)
		and not hospital_card.disabled
		and hospital_status.text == "DRAG TO PLAY",
		"Hospital Run should remain interactive even when no hospital exists."
	)
	await _drag_card_to_self(hospital_card, card_controller)
	_expect(
		player.get_card_quantity(EMERGENCY_TRANSFER) == 2
		and not hospital_card.is_being_dragged(),
		"Releasing Hospital Run without a hospital should return the card to its hand."
	)
	_expect(
		not (await game_manager.request_play_card(player, EMERGENCY_TRANSFER))
		and player.get_card_quantity(EMERGENCY_TRANSFER) == 2,
		"A rejected hospital card should remain in the hand."
	)

	var hospital_index := 2
	var hospital := board.get_plot(hospital_index)
	hospital.set_plot_owner(player)
	_expect(
		game_manager.request_construct_building(player, hospital, MEDIC_TOWER),
		"The owner should be able to build a Medic Tower during their turn."
	)
	_expect(
		game_manager.can_play_card(player, EMERGENCY_TRANSFER)
		and not hospital_card.disabled,
		"A newly built Medic Tower should pass Hospital Run's release-time legality check."
	)
	board.register_entity(player, board.plots.size() - 2)
	player.set_health(50)
	var money_before_travel := player.money
	var expected_lap_income := board.get_owned_property_income(player)
	var resolved_results: Array = []
	game_manager.card_played.connect(
		func(result) -> void:
			resolved_results.append(result)
	)
	_expect(
		game_manager.can_play_card(player, EMERGENCY_TRANSFER),
		"A forward Medic Tower should make Emergency Transfer playable."
	)
	await _drag_card_to_self(hospital_card, card_controller)
	_expect(
		board.get_entity_plot_index(player) == hospital_index,
		"Emergency Transfer should stop on the nearest forward hospital."
	)
	_expect(
		player.money == money_before_travel + expected_lap_income,
		"Hospital travel that crosses Start should award normal lap income."
	)
	_expect(
		player.health == 50 + MEDIC_TOWER.healing,
		"The destination Medic Tower should still perform its owner heal."
	)
	_expect(
		resolved_results.size() == 1
		and resolved_results[0].outcome
			== CARD_PLAY_RESULT_SCRIPT.Outcome.MOVED_TO_HOSPITAL
		and resolved_results[0].destination_index == hospital_index,
		"Hospital travel should publish its resolved destination."
	)
	_expect(
		not game_manager.has_active_entity_rolled()
		and game_manager.has_roll_available()
		and turn_action_button.text == "Roll Dice",
		"Hospital travel should not consume the player's normal roll."
	)
	_expect(
		player.get_card_quantity(EMERGENCY_TRANSFER) == 1
		and not game_manager.can_play_card(player, EMERGENCY_TRANSFER)
		and not (await game_manager.request_play_card(player, EMERGENCY_TRANSFER))
		and player.get_card_quantity(EMERGENCY_TRANSFER) == 1,
		"Hospital Run should reject a second use by the same player in one round without consuming it."
	)

	var fixed_roll: Array[int] = [1, 1]
	await game_manager.play_active_turn(fixed_roll)
	if game_manager.has_pending_purchase():
		game_manager.request_property_purchase(player, false)
	_expect(
		game_manager.request_end_turn(player),
		"The Hospital Run user should still be able to finish their normal turn."
	)
	var opponent := game_screen.get_node("Player2") as Entity
	await game_manager.play_active_turn(fixed_roll)
	_expect(
		game_manager.request_end_turn(opponent),
		"The opposing turn should advance the match into the next round."
	)
	_expect(
		game_manager.round_number == 2
		and game_manager.get_active_entity() == player
		and game_manager.can_play_card(player, EMERGENCY_TRANSFER),
		"Hospital Run should become usable again for that player in the next round."
	)

	game_screen.queue_free()
	await process_frame


func _test_card_target_validation() -> void:
	var game_session := root.get_node("GameSession")
	game_session.set("participant_count", 2)
	var game_screen := GAME_SCENE.instantiate()
	root.add_child(game_screen)
	await process_frame
	var game_manager := game_screen.get_node("GameManager") as GameManager
	var board := game_screen.get_node("Board") as Board
	var player := game_screen.get_node("Player") as Entity
	game_manager.auto_play_ai = false

	var property_card := CardData.new()
	property_card.card_id = &"property_target_test"
	property_card.display_name = "Property Target Test"
	property_card.effect = CardData.EffectType.END_TURN_WITHOUT_ROLL
	property_card.target_mode = CardData.TargetMode.PROPERTY
	player.add_card(property_card)
	var ownable_plot := _get_first_ownable_plots(board, 1)[0]
	_expect(
		not game_manager.can_target_card(player, property_card)
		and game_manager.can_target_card(player, property_card, ownable_plot)
		and not game_manager.can_target_card(player, property_card, board.get_plot(0)),
		"Property-targeted cards should require a real ownable board property."
	)
	player.remove_card(property_card)

	game_screen.queue_free()
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
	var actions := game_screen.get_node("GameUI/Actions") as HBoxContainer
	var turn_action_button := game_screen.get_node(
		"GameUI/Actions/TurnActionButton"
	) as Button
	var owned_properties_rail := game_screen.get_node(
		"GameUI/OwnedPropertiesRail"
	) as Control
	var owned_properties_list := game_screen.get_node(
		"GameUI/OwnedPropertiesRail/Scroll/OwnedPropertiesList"
	) as VBoxContainer
	var game_camera := game_screen.get_node("Camera3D") as GameCamera
	var player_status_panel := game_screen.get_node(
		"GameUI/PlayerStatusPanel"
	) as PanelContainer
	var health_bar := game_screen.get_node(
		"GameUI/PlayerStatusPanel/Margin/Content/HealthArea/HealthBar"
	) as ProgressBar
	var health_label := game_screen.get_node(
		"GameUI/PlayerStatusPanel/Margin/Content/HealthArea/HealthLabel"
	) as Label
	var money_label := game_screen.get_node(
		"GameUI/PlayerStatusPanel/Margin/Content/MoneyLabel"
	) as Label
	var roll_result_label := game_screen.get_node(
		"GameUI/RollResultLabel"
	) as Label
	var rolled_entities: Array[Entity] = []
	game_manager.dice_rolled.connect(
		func(entity: Entity, _dice_values: Array[int]) -> void:
			rolled_entities.append(entity)
	)

	board.movement_units_per_second = 1000.0
	game_manager.ai_roll_delay = 0.01
	_expect(
		game_screen.has_node("PresentationSystems/TurnHudController")
		and game_screen.has_node("PresentationSystems/WorldActionController")
		and game_screen.has_node("PresentationSystems/OwnedPropertyRailController")
		and game_screen.has_node("PresentationSystems/BuildingPaletteController")
		and game_manager.has_node("PropertyActionSystem")
		and game_manager.has_node("AiTurnController")
		and board.has_node("BuildingEffectSystem"),
		"The playable scene should compose gameplay and presentation as separate systems."
	)
	_expect(actions.get_child_count() == 1, "The HUD should use one turn action button.")
	_expect(turn_action_button.text == "Roll Dice", "The turn action should begin as Roll Dice.")
	_expect(
		player_status_panel.size.y <= 90.0,
		"The top-left player status should remain compact."
	)
	_expect(health_bar.value == local_player.health, "The health bar should show local health.")
	_expect(health_label.text.contains("100 / 100"), "The health bar should show its value.")
	_expect(money_label.text.contains("$1200"), "The compact status should show local funds.")
	_expect(
		not roll_result_label.visible and roll_result_label.text.is_empty(),
		"The dice result should stay out of the HUD until somebody rolls."
	)
	_expect(
		roll_result_label.get_parent() == game_screen.get_node("GameUI"),
		"The dice result should live outside the top-left player status."
	)
	_expect(
		not game_screen.has_node("GameUI/TurnStatus/HintLabel"),
		"The HUD should not reserve space for instructional hints."
	)
	_expect(
		is_equal_approx(
			roll_result_label.global_position.x + roll_result_label.size.x,
			turn_action_button.global_position.x + turn_action_button.size.x
		),
		"The dice result should share the turn button's right edge."
	)
	_expect(
		is_equal_approx(roll_result_label.size.x, turn_action_button.size.x),
		"The dice result should use the turn button's width."
	)
	local_player.take_damage(25)
	_expect(health_bar.value == 75.0, "The health bar should react to local damage.")
	_expect(health_label.text.contains("75 / 100"), "The health value should react to damage.")
	local_player.heal(25)
	_expect(not owned_properties_rail.visible, "The deed rail should disappear when nothing is owned.")
	_expect(owned_properties_list.get_child_count() == 0, "The deed list should begin empty.")
	var first_property := board.get_plot(1)
	var second_property := board.get_plot(2)
	_expect(
		first_property.get_property_value() != second_property.get_property_value(),
		"Individual property plots should have distinct rent values."
	)
	_expect(
		first_property.get_buy_price() != second_property.get_buy_price(),
		"Individual property plots should have distinct buy prices."
	)
	_expect(
		first_property.get_tower_rent() != second_property.get_tower_rent(),
		"Individual property plots should have distinct tower rents."
	)

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
	for participant in game_manager.participants:
		_expect(participant.money == 1200, "Each participant should begin with $1,200.")
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
	var offered_plot := game_manager.get_pending_purchase_plot()
	_expect(
		is_instance_valid(offered_plot),
		"Landing on an unowned property should leave a purchase decision pending."
	)
	_expect(
		game_manager.get_active_entity() == local_player,
		"A purchase offer should not advance the turn on its own."
	)
	var world_action_panel := game_screen.get_node("GameUI/WorldActionPanel") as PanelContainer
	var world_action_title := game_screen.get_node(
		"GameUI/WorldActionPanel/Margin/Content/WorldActionTitle"
	) as Label
	var world_action_details := game_screen.get_node(
		"GameUI/WorldActionPanel/Margin/Content/WorldActionDetails"
	) as Label
	var buy_property_button := game_screen.get_node(
		"GameUI/WorldActionPanel/Margin/Content/Buttons/BuyButton"
	) as Button
	var skip_property_button := game_screen.get_node(
		"GameUI/WorldActionPanel/Margin/Content/Buttons/DeclineButton"
	) as Button
	var building_palette := game_screen.get_node(
		"GameUI/BuildingPalette"
	) as PanelContainer
	_expect(turn_action_button.visible, "Property offers should not replace the turn action.")
	_expect(turn_action_button.text == "End Turn", "The action should switch after rolling.")
	_expect(not turn_action_button.disabled, "A purchase offer should not disable End Turn.")
	_expect(world_action_panel.visible, "A property offer should appear in its world action menu.")
	_expect(
		roll_result_label.visible and roll_result_label.text.contains("1 + 1 = 2"),
		"The dice result should appear only after the roll and show its total."
	)
	_expect(
		not buy_property_button.disabled,
		"Buy should enable when movement finishes and the property is affordable."
	)
	_expect(
		not world_action_details.text.contains("Unowned property")
		and not building_palette.visible,
		"A landing decision should hide unrelated construction UI and avoid redundant copy."
	)
	var purchased_property_deed: Button
	var resting_deed_x := 0.0
	if is_instance_valid(offered_plot):
		_expect(
			world_action_title.text == offered_plot.data.display_name
			and world_action_details.text.contains(
				"Lap +$%d" % offered_plot.get_base_rent()
			)
			and world_action_details.text.contains(
				"Hotel rent $%d" % offered_plot.get_tower_rent()
			),
			"The purchase menu should expose the property's lap income and upgraded rent."
		)
		_expect(
			buy_property_button.text == "Buy  $%d" % offered_plot.get_buy_price()
			and skip_property_button.text == "Skip",
			"The purchase choices should be concise and state the price once."
		)
		var money_before_purchase := local_player.money
		var offered_price := offered_plot.get_buy_price()
		buy_property_button.pressed.emit()
		_expect(
			offered_plot.plot_owner == local_player,
			"Accepting the offer should assign ownership to the buyer."
		)
		_expect(
			local_player.money == money_before_purchase - offered_price,
			"Accepting the offer should deduct that plot's configured buy price."
		)
		_expect(owned_properties_rail.visible, "Buying a property should reveal the deed edge rail.")
		_expect(
			owned_properties_list.get_child_count() == 1,
			"Buying a property should add one deed to the owned-property list."
		)
		purchased_property_deed = _get_property_deed(owned_properties_list, 0)
		_expect(
			purchased_property_deed.text.contains(offered_plot.data.display_name),
			"A property deed should identify its owned plot."
		)
		_expect(
			purchased_property_deed.tooltip_text.is_empty(),
			"Property deeds should not display hover tooltip text."
		)
		_expect(
			purchased_property_deed.text.contains(
				"Lap +$%d" % offered_plot.get_base_rent()
			)
			and purchased_property_deed.has_node("FaceMargin/Rows/EconomyRow")
			and not purchased_property_deed.text.contains("Plot "),
			"A deed should show structured decision data without repeating its board index."
		)
		resting_deed_x = purchased_property_deed.position.x
		_expect(resting_deed_x < 0.0, "A resting property deed should remain mostly off-screen.")
		purchased_property_deed.mouse_entered.emit()
		await create_timer(0.1).timeout
		_expect(
			purchased_property_deed.position.x > resting_deed_x,
			"Hovering a deed tab should begin sliding the card onto the screen."
		)
		_expect(
			game_camera.target == offered_plot,
			"Hovering an owned deed while idle should focus its board plot."
		)
		purchased_property_deed.pressed.emit()
		purchased_property_deed.mouse_exited.emit()
		await create_timer(0.25).timeout
		_expect(
			game_camera.target == offered_plot,
			"A selected deed should remain the camera's default anchor."
		)
		_expect(
			absf(purchased_property_deed.position.x) < 0.5,
			"Selecting a deed should keep it extended after the hover ends."
		)
		_expect(
			purchased_property_deed.button_pressed,
			"The selected deed should retain a visible selected state."
		)
		purchased_property_deed.button_pressed = false
		purchased_property_deed.pressed.emit()
		await create_timer(0.25).timeout
		_expect(
			game_screen.get_selected_property() == null,
			"Clicking the selected deed again should clear the selection."
		)
		_expect(
			purchased_property_deed.position.x <= resting_deed_x + 0.5,
			"Deselecting a deed should retract it."
		)
		_expect(
			game_camera.target == local_player,
			"Deselecting should restore the active player as the camera anchor."
		)
		purchased_property_deed.button_pressed = true
		purchased_property_deed.pressed.emit()
		await create_timer(0.25).timeout
		_expect(
			game_screen.get_selected_property() == offered_plot,
			"A deselected deed should be selectable again."
		)
		_expect(
			building_palette.visible,
			"An owned, unbuilt selected deed should reveal construction choices."
		)
	_expect(
		game_manager.request_turn_action(local_player),
		"End Turn should advance after human movement completes."
	)
	await create_timer(0.25).timeout
	if is_instance_valid(purchased_property_deed):
		_expect(
			purchased_property_deed.position.x <= resting_deed_x + 0.5,
			"A selected deed should retract when the local player's turn ends."
		)
		_expect(
			not purchased_property_deed.button_pressed,
			"The deed selection should clear when the local player's turn ends."
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


func _get_property_deed(deed_list: VBoxContainer, index: int) -> Button:
	if index < 0 or index >= deed_list.get_child_count():
		return null
	var deed_slot := deed_list.get_child(index)
	if deed_slot.get_child_count() == 0:
		return null
	return deed_slot.get_child(0) as Button


func _get_first_ownable_plots(board: Board, count: int) -> Array[Plot]:
	var ownable_plots: Array[Plot] = []
	for plot in board.plots:
		if plot.data != null and plot.data.is_ownable():
			ownable_plots.append(plot)
			if ownable_plots.size() == count:
				break
	return ownable_plots


func _move_entity_to_plot(board: Board, entity: Entity, destination: Plot) -> int:
	var destination_index := board.plots.find(destination)
	if destination_index == -1:
		return -1
	board.register_entity(entity, destination_index - 2)
	var fixed_roll: Array[int] = [1, 1]
	return await board.move_entity(entity, fixed_roll)


func _drag_card_to_self(card_button: Button, card_controller: Node) -> void:
	card_controller.set_hand_revealed(true, true)
	var cast_position: Vector2 = card_controller.get_self_cast_rect().get_center()
	_simulate_card_drag(card_button, cast_position)
	await create_timer(0.65).timeout


func _simulate_card_drag(card_button: Button, target_position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = card_button.size * 0.5
	card_button._gui_input(press)

	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = (
		card_button.get_global_transform_with_canvas().affine_inverse()
		* target_position
	)
	card_button._gui_input(motion)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = (
		card_button.get_global_transform_with_canvas().affine_inverse()
		* target_position
	)
	card_button._gui_input(release)
	# A real cast immediately moves away from the cursor. This used to cancel
	# the cast tween and leave the hand stuck in PLAYING before the command ran.
	card_button.mouse_exited.emit()


func _get_feedback_label(entity: Entity, kind: StringName) -> Label3D:
	for child in entity.get_children():
		if (
			child is Label3D
			and child.has_meta(&"feedback_kind")
			and child.get_meta(&"feedback_kind") == kind
		):
			return child as Label3D
	return null


func _color_distance(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_to(
		Vector3(second.r, second.g, second.b)
	)
