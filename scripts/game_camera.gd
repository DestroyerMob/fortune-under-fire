class_name GameCamera
extends Camera3D

signal target_changed(previous_target: Node3D, new_target: Node3D)
signal target_movement_changed(is_moving: bool)

@export var settings: CameraSettings
@export var initial_target: Node3D
## A Board provides the four edge directions and four 45-degree corner views.
@export var orbit_center: Node3D
## Set this on each client if LOCAL_PLAYER_ONLY is available as an account
## preference. Leave it empty for spectators and fully AI games.
@export var local_player: Node3D

var target: Node3D

var _last_target_position := Vector3.ZERO
var _target_velocity := Vector3.ZERO
var _view_angle := 0.0
var _follow_distance := 0.0
var _elevation_angle := 0.0
var _smoothed_focus_position := Vector3.ZERO
var _movement_blend := 0.0
var _time_since_target_moved := 0.0
var _target_is_moving := false
var _event_hold_generation := 0
var _event_hold_active := false
var _pending_turn_target: Node3D
var _pending_turn_snap := false


func _ready() -> void:
	if settings == null:
		settings = CameraSettings.new()
	if settings.force_orthographic_projection:
		projection = PROJECTION_ORTHOGONAL

	if initial_target != null:
		track_target(initial_target, true)
	else:
		set_process(false)


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		target = null
		set_process(false)
		return

	_update_target_motion(delta)
	_update_view(delta)


## Call this when the active turn changes. The local account's TargetMode is
## applied here, so ALL_TURNS follows humans and AI without special cases.
func focus_turn_target(turn_target: Node3D, snap := false) -> void:
	if _event_hold_active:
		_pending_turn_target = turn_target
		_pending_turn_snap = snap
		return
	if settings.target_mode == CameraSettings.TargetMode.LOCAL_PLAYER_ONLY:
		if is_instance_valid(local_player):
			track_target(local_player, snap)
		return

	track_target(turn_target, snap)


## Keeps an important event on-screen even if the match advances to another
## turn meanwhile. The latest requested turn target is restored after the hold.
func hold_event_target(event_target: Node3D, duration: float) -> void:
	if not is_instance_valid(event_target) or duration <= 0.0:
		return
	var was_holding := _event_hold_active
	_event_hold_generation += 1
	var generation := _event_hold_generation
	_event_hold_active = true
	if not was_holding:
		_pending_turn_target = null
		_pending_turn_snap = false
	track_target(event_target)
	_release_event_hold_after(duration, generation)


func is_holding_event_target() -> bool:
	return _event_hold_active


func _release_event_hold_after(duration: float, generation: int) -> void:
	await get_tree().create_timer(duration).timeout
	if generation != _event_hold_generation:
		return
	_event_hold_active = false
	var next_target := _pending_turn_target
	var should_snap := _pending_turn_snap
	_pending_turn_target = null
	_pending_turn_snap = false
	if is_instance_valid(next_target):
		focus_turn_target(next_target, should_snap)


## Low-level focus method for cutscenes, selection previews, and spectators.
## Unlike focus_turn_target(), this intentionally bypasses TargetMode.
func track_target(new_target: Node3D, snap := false) -> void:
	if new_target == target:
		if snap and is_instance_valid(target):
			_snap_to_target()
		return

	var previous_target := target
	target = new_target

	if not is_instance_valid(target):
		set_process(false)
		target_changed.emit(previous_target, target)
		return

	var should_snap := snap or settings.snap_on_target_change
	_last_target_position = target.global_position
	_target_velocity = Vector3.ZERO
	if not is_instance_valid(previous_target):
		_smoothed_focus_position = target.global_position + settings.target_focus_offset
	_movement_blend = 0.0
	_time_since_target_moved = settings.movement_settle_duration
	_set_target_is_moving(false)
	set_process(true)

	if should_snap:
		_snap_to_target()

	target_changed.emit(previous_target, target)


func clear_target() -> void:
	track_target(null)


func is_target_moving() -> bool:
	return _target_is_moving


func _update_target_motion(delta: float) -> void:
	var current_target_position := target.global_position
	var safe_delta := maxf(delta, 0.000001)
	_target_velocity = (current_target_position - _last_target_position) / safe_delta
	_last_target_position = current_target_position

	var horizontal_speed := Vector2(_target_velocity.x, _target_velocity.z).length()
	if horizontal_speed >= settings.movement_speed_threshold:
		_time_since_target_moved = 0.0
		_set_target_is_moving(true)
	else:
		_time_since_target_moved += delta
		if _time_since_target_moved >= settings.movement_settle_duration:
			_set_target_is_moving(false)

	var desired_blend := 1.0 if settings.dynamic_movement_view and _target_is_moving else 0.0
	_movement_blend = lerpf(
		_movement_blend,
		desired_blend,
		_smoothing_weight(settings.view_blend_speed, delta)
	)


func _update_view(delta: float) -> void:
	var desired_angle := _get_target_view_angle()
	var desired_focus_position := target.global_position + settings.target_focus_offset
	var desired_follow_distance := lerpf(
		settings.stationary_follow_distance,
		settings.moving_follow_distance,
		_movement_blend
	)
	var desired_elevation_angle := lerpf(
		settings.stationary_elevation_angle,
		settings.moving_elevation_angle,
		_movement_blend
	)
	var rotation_weight := _smoothing_weight(settings.rotation_smoothing_speed, delta)
	var follow_weight := _smoothing_weight(settings.follow_smoothing_speed, delta)
	var framing_weight := _smoothing_weight(settings.framing_smoothing_speed, delta)

	_view_angle = lerp_angle(_view_angle, desired_angle, rotation_weight)
	_smoothed_focus_position = _smoothed_focus_position.lerp(
		desired_focus_position,
		follow_weight
	)
	_follow_distance = lerpf(_follow_distance, desired_follow_distance, framing_weight)
	_elevation_angle = lerpf(_elevation_angle, desired_elevation_angle, framing_weight)
	_apply_camera_transform()

	_update_zoom(delta)


func _get_target_view_angle() -> float:
	var outward_direction := Vector3.ZERO
	if orbit_center is Board and target is Entity:
		outward_direction = (orbit_center as Board).get_entity_outward_direction(target)

	# Fallback for cutscene or spectator targets that are not registered entities.
	if outward_direction.length_squared() <= 0.000001:
		outward_direction = target.global_position - _get_orbit_centre()
		outward_direction.y = 0.0

	if outward_direction.length_squared() <= 0.000001:
		return _view_angle
	return atan2(outward_direction.z, outward_direction.x)


func _get_orbit_centre() -> Vector3:
	if is_instance_valid(orbit_center):
		return orbit_center.global_position
	return Vector3.ZERO


func _apply_camera_transform() -> void:
	var outward_direction := Vector3(cos(_view_angle), 0.0, sin(_view_angle))
	var focus_position := _smoothed_focus_position

	# Every edge uses a fixed inward-facing view. Only corners rotate it by 45
	# degrees, so travelling along one side never causes unwanted camera yaw.
	var camera_height := (
		tan(deg_to_rad(_elevation_angle))
		* _follow_distance
	)
	global_position = (
		focus_position
		+ outward_direction * _follow_distance
		+ Vector3.UP * camera_height
	)

	# The entity remains the exact focal point. Rebuilding this basis directly also
	# avoids rotational interpolation flicker.
	look_at(focus_position, Vector3.UP)


func _update_zoom(delta: float) -> void:
	var zoom_weight := _smoothing_weight(settings.zoom_smoothing_speed, delta)
	if projection == PROJECTION_PERSPECTIVE:
		var desired_fov := lerpf(settings.stationary_fov, settings.moving_fov, _movement_blend)
		fov = lerpf(fov, desired_fov, zoom_weight)
	else:
		var desired_size := lerpf(
			settings.stationary_orthographic_size,
			settings.moving_orthographic_size,
			_movement_blend
		)
		size = lerpf(size, desired_size, zoom_weight)


func _snap_to_target() -> void:
	_movement_blend = 0.0
	_view_angle = _get_target_view_angle()
	_follow_distance = settings.stationary_follow_distance
	_elevation_angle = settings.stationary_elevation_angle
	_smoothed_focus_position = target.global_position + settings.target_focus_offset
	_apply_camera_transform()

	if projection == PROJECTION_PERSPECTIVE:
		fov = settings.stationary_fov
	else:
		size = settings.stationary_orthographic_size


func _smoothing_weight(speed: float, delta: float) -> float:
	if not settings.smooth_transitions:
		return 1.0
	return 1.0 - exp(-speed * delta)


func _set_target_is_moving(value: bool) -> void:
	if value == _target_is_moving:
		return

	_target_is_moving = value
	target_movement_changed.emit(_target_is_moving)
