class_name EntityPresenter
extends RefCounted

const HEALTH_INDICATOR_HEIGHT := 1.42
const HEALTH_BAR_WIDTH := 0.82
const HEALTH_BAR_HEIGHT := 0.095
const FEEDBACK_START_HEIGHT := 1.62
const FEEDBACK_RISE_DISTANCE := 0.3
const FEEDBACK_DURATION := 0.82

var _entity: Entity
var _health_indicator: Node3D
var _health_fill: MeshInstance3D
var _health_fill_material: StandardMaterial3D
var _body_material: StandardMaterial3D
var _body_feedback_tween: Tween
var _active_feedback_count := 0


func configure(entity: Entity) -> void:
	_entity = entity
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _entity.color
	_body_material.roughness = 0.35
	_entity.material_override = _body_material
	_create_health_indicator()
	refresh_health()


func refresh_health() -> void:
	if not is_instance_valid(_health_indicator):
		return
	var health_ratio := _entity.get_health_indicator_ratio()
	if is_instance_valid(_health_fill):
		_health_fill.scale.x = maxf(health_ratio, 0.001)
	if _health_fill_material != null:
		_health_fill_material.albedo_color = (
			Color(0.35, 1.0, 0.55, 1.0)
			if health_ratio > 0.6
			else (
				Color(1.0, 0.78, 0.22, 1.0)
				if health_ratio > 0.3
				else Color(1.0, 0.25, 0.18, 1.0)
			)
		)


func play_money_feedback(amount: int) -> void:
	if amount == 0:
		return
	var sign_text := "+" if amount > 0 else "−"
	var feedback_color := (
		Color(0.35, 1.0, 0.55, 1.0)
		if amount > 0
		else Color(1.0, 0.66, 0.22, 1.0)
	)
	_play_floating_feedback(
		"%s$%d" % [sign_text, absi(amount)],
		feedback_color,
		&"money"
	)


func play_damage_feedback(amount: int) -> void:
	if amount <= 0:
		return
	_play_floating_feedback(
		"−%d" % amount,
		Color(1.0, 0.24, 0.18, 1.0),
		&"damage"
	)
	_flash_body(Color(1.0, 0.18, 0.12, 1.0))


func play_healing_feedback(amount: int) -> void:
	if amount <= 0:
		return
	_play_floating_feedback(
		"+%d" % amount,
		Color(0.32, 1.0, 0.68, 1.0),
		&"healing"
	)
	_flash_body(Color(0.28, 1.0, 0.62, 1.0))


func get_active_feedback_count() -> int:
	return _active_feedback_count


func has_active_feedback_kind(kind: StringName) -> bool:
	for child in _entity.get_children():
		if (
			child is Label3D
			and child.has_meta(&"feedback_kind")
			and child.get_meta(&"feedback_kind") == kind
		):
			return true
	return false


func get_health_indicator() -> Node3D:
	return _health_indicator if is_instance_valid(_health_indicator) else null


func _create_health_indicator() -> void:
	_health_indicator = Node3D.new()
	_health_indicator.name = "HealthIndicator"
	_health_indicator.position = Vector3.UP * HEALTH_INDICATOR_HEIGHT
	_entity.add_child(_health_indicator)

	var background := MeshInstance3D.new()
	background.name = "Background"
	var background_mesh := QuadMesh.new()
	background_mesh.size = Vector2(
		HEALTH_BAR_WIDTH + 0.06,
		HEALTH_BAR_HEIGHT + 0.05
	)
	background.mesh = background_mesh
	background.material_override = _create_indicator_material(
		Color(0.025, 0.03, 0.045, 0.9)
	)
	_health_indicator.add_child(background)

	_health_fill = MeshInstance3D.new()
	_health_fill.name = "Fill"
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_fill.mesh = fill_mesh
	_health_fill.position.z = 0.002
	_health_fill_material = _create_indicator_material(
		Color(0.3, 0.92, 0.46, 1.0)
	)
	_health_fill.material_override = _health_fill_material
	_health_indicator.add_child(_health_fill)


func _create_indicator_material(indicator_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = indicator_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	return material


func _flash_body(flash_color: Color) -> void:
	if _body_material == null:
		return
	if _body_feedback_tween != null and _body_feedback_tween.is_valid():
		_body_feedback_tween.kill()
	_body_material.albedo_color = flash_color
	_body_feedback_tween = _entity.create_tween().bind_node(_entity)
	_body_feedback_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_body_feedback_tween.tween_property(
		_body_material,
		^"albedo_color",
		_entity.color,
		0.32
	)


func _play_floating_feedback(
	feedback_text: String,
	feedback_color: Color,
	feedback_kind: StringName
) -> void:
	var feedback := Label3D.new()
	feedback.name = "FloatingFeedback"
	feedback.position = Vector3.UP * (
		FEEDBACK_START_HEIGHT + minf(float(_active_feedback_count), 3.0) * 0.16
	)
	feedback.text = feedback_text
	feedback.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback.no_depth_test = true
	feedback.fixed_size = false
	feedback.pixel_size = 0.006
	feedback.font_size = 26
	feedback.outline_size = 5
	feedback.modulate = feedback_color
	feedback.outline_modulate = Color(0.02, 0.025, 0.035, 0.96)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.set_meta(&"feedback_kind", feedback_kind)
	_entity.add_child(feedback)
	_active_feedback_count += 1

	var feedback_tween := _entity.create_tween().bind_node(feedback)
	feedback_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	feedback.scale = Vector3.ONE * 0.82
	feedback_tween.parallel().tween_property(feedback, ^"scale", Vector3.ONE, 0.16)
	feedback_tween.parallel().tween_property(
		feedback,
		^"position:y",
		feedback.position.y + FEEDBACK_RISE_DISTANCE,
		FEEDBACK_DURATION
	)
	feedback_tween.parallel().tween_property(
		feedback,
		^"modulate:a",
		0.0,
		FEEDBACK_DURATION * 0.72
	).set_delay(FEEDBACK_DURATION * 0.28)
	feedback_tween.finished.connect(
		func() -> void:
			_active_feedback_count = maxi(_active_feedback_count - 1, 0)
			if is_instance_valid(feedback):
				feedback.queue_free()
	)
