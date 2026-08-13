class_name PlotPresenter
extends RefCounted

var _plot: Plot
var _top_mesh: MeshInstance3D
var _owner_marker: Node3D
var _owner_flag: MeshInstance3D
var _owner_label: Label3D
var _tower_mesh: MeshInstance3D


func configure(plot: Plot) -> void:
	_plot = plot
	_top_mesh = _plot.get_node_or_null(^"Top") as MeshInstance3D
	_owner_marker = _plot.get_node_or_null(^"OwnerMarker") as Node3D
	_owner_flag = _plot.get_node_or_null(^"OwnerMarker/Flag") as MeshInstance3D
	_owner_label = _plot.get_node_or_null(^"OwnerMarker/OwnerLabel") as Label3D
	_tower_mesh = _plot.get_node_or_null(^"Tower") as MeshInstance3D
	refresh_all()


func refresh_all() -> void:
	refresh_plot()
	refresh_owner()
	refresh_building()


func refresh_plot() -> void:
	if _top_mesh == null or _plot.data == null:
		return
	var top_material := StandardMaterial3D.new()
	top_material.albedo_color = _plot.data.get_top_color()
	top_material.roughness = 0.55
	_top_mesh.material_override = top_material


func refresh_owner() -> void:
	if _owner_marker == null:
		return
	var has_owner := is_instance_valid(_plot.plot_owner)
	_owner_marker.visible = has_owner
	if not has_owner:
		return
	var owner_color := _plot.plot_owner.color
	if _owner_flag != null:
		var flag_material := StandardMaterial3D.new()
		flag_material.albedo_color = owner_color
		flag_material.emission_enabled = true
		flag_material.emission = owner_color
		flag_material.emission_energy_multiplier = 0.3
		flag_material.roughness = 0.45
		_owner_flag.material_override = flag_material
	if _owner_label != null:
		_owner_label.text = "Owned by %s" % _plot.plot_owner.get_display_name()
		_owner_label.modulate = owner_color.lightened(0.2)


func refresh_building() -> void:
	if _tower_mesh == null:
		return
	var has_visual := _plot.building != null or _plot.has_tower
	_tower_mesh.visible = has_visual
	if not has_visual or _plot.data == null:
		return

	if _plot.building != null:
		_tower_mesh.mesh = _create_building_mesh(_plot.building.type)
	else:
		var legacy_mesh := CylinderMesh.new()
		legacy_mesh.top_radius = 0.2
		legacy_mesh.bottom_radius = 0.3
		legacy_mesh.height = 0.62
		legacy_mesh.radial_segments = 6
		_tower_mesh.mesh = legacy_mesh

	var visual_color := (
		_plot.building.color
		if _plot.building != null
		else _plot.data.get_top_color().darkened(0.2)
	)
	var tower_material := StandardMaterial3D.new()
	tower_material.albedo_color = visual_color
	tower_material.emission_enabled = (
		_plot.building != null
		and _plot.building.type == BuildingData.BuildingType.TESLA_COIL
	)
	if tower_material.emission_enabled:
		tower_material.emission = visual_color
		tower_material.emission_energy_multiplier = 0.65
	tower_material.metallic = 0.25
	tower_material.roughness = 0.55
	_tower_mesh.material_override = tower_material


func play_building_activation() -> void:
	if _tower_mesh == null or not _tower_mesh.visible:
		return
	if _tower_mesh.has_meta(&"activation_tween"):
		var previous_tween := _tower_mesh.get_meta(&"activation_tween") as Tween
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()
	_tower_mesh.scale = Vector3.ONE
	var activation_tween := _plot.create_tween().bind_node(_tower_mesh)
	activation_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	activation_tween.tween_property(_tower_mesh, ^"scale", Vector3.ONE * 1.28, 0.12)
	activation_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	activation_tween.tween_property(_tower_mesh, ^"scale", Vector3.ONE, 0.24)
	_tower_mesh.set_meta(&"activation_tween", activation_tween)


func _create_building_mesh(building_type: BuildingData.BuildingType) -> PrimitiveMesh:
	match building_type:
		BuildingData.BuildingType.APARTMENTS:
			var apartments := BoxMesh.new()
			apartments.size = Vector3(0.52, 0.88, 0.52)
			return apartments
		BuildingData.BuildingType.HOTEL:
			var hotel := BoxMesh.new()
			hotel.size = Vector3(0.78, 0.68, 0.54)
			return hotel
		BuildingData.BuildingType.CASINO:
			var casino := CylinderMesh.new()
			casino.top_radius = 0.38
			casino.bottom_radius = 0.38
			casino.height = 0.46
			casino.radial_segments = 8
			return casino
		BuildingData.BuildingType.GUN_TOWER:
			var gun_tower := CylinderMesh.new()
			gun_tower.top_radius = 0.16
			gun_tower.bottom_radius = 0.28
			gun_tower.height = 0.82
			gun_tower.radial_segments = 8
			return gun_tower
		BuildingData.BuildingType.ARTILLERY_BATTERY:
			var artillery := BoxMesh.new()
			artillery.size = Vector3(0.86, 0.38, 0.64)
			return artillery
		BuildingData.BuildingType.TESLA_COIL:
			var tesla := CylinderMesh.new()
			tesla.top_radius = 0.09
			tesla.bottom_radius = 0.32
			tesla.height = 0.94
			tesla.radial_segments = 6
			return tesla
		BuildingData.BuildingType.MEDIC_TOWER:
			var medic := PrismMesh.new()
			medic.size = Vector3(0.66, 0.82, 0.66)
			return medic
		BuildingData.BuildingType.BANK:
			var bank := BoxMesh.new()
			bank.size = Vector3(0.82, 0.58, 0.68)
			return bank
	var fallback := BoxMesh.new()
	fallback.size = Vector3(0.5, 0.5, 0.5)
	return fallback
