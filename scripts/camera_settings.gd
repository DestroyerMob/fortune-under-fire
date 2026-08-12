class_name CameraSettings
extends Resource

## Controls which turn target this local camera follows. Camera preferences are
## presentation-only state and should not be replicated over the network.
enum TargetMode {
	ALL_TURNS,
	LOCAL_PLAYER_ONLY,
}

@export_category("Target Tracking")
@export var target_mode: TargetMode = TargetMode.ALL_TURNS
## Optional cinematic framing. Disabled by default so movement never changes
## board scale or pitch unless the local account explicitly enables it.
@export var dynamic_movement_view := false
@export var snap_on_target_change := false
@export_range(0.001, 5.0, 0.001) var movement_speed_threshold := 0.05
@export_range(0.0, 2.0, 0.01) var movement_settle_duration := 0.2

@export_category("Projection")
## Orthographic projection keeps every plot the same apparent size regardless
## of its distance from the camera.
@export var force_orthographic_projection := true

@export_category("Stationary View")
@export_range(1.0, 50.0, 0.1) var stationary_follow_distance := 9.0
@export_range(5.0, 85.0, 0.1, "degrees") var stationary_elevation_angle := 40.0
@export_range(1.0, 50.0, 0.1) var stationary_orthographic_size := 12.0
@export_range(1.0, 179.0, 0.1) var stationary_fov := 50.0

@export_category("Moving View")
@export_range(1.0, 50.0, 0.1) var moving_follow_distance := 9.0
@export_range(5.0, 85.0, 0.1, "degrees") var moving_elevation_angle := 40.0
@export_range(1.0, 50.0, 0.1) var moving_orthographic_size := 12.0
@export_range(1.0, 179.0, 0.1) var moving_fov := 50.0

@export_category("Framing")
## The camera aims at this offset from the tracked entity.
@export var target_focus_offset := Vector3(0.0, 0.5, 0.0)

@export_category("Smoothing")
@export var smooth_transitions := true
## How quickly the camera catches up when the tracked entity changes plots.
@export_range(0.1, 30.0, 0.1) var follow_smoothing_speed := 4.5
@export_range(0.1, 30.0, 0.1) var rotation_smoothing_speed := 7.0
@export_range(0.1, 30.0, 0.1) var framing_smoothing_speed := 6.0
@export_range(0.1, 30.0, 0.1) var zoom_smoothing_speed := 7.0
@export_range(0.1, 30.0, 0.1) var view_blend_speed := 5.0
