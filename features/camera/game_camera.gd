class_name GameCamera
extends Camera2D

## Standalone world camera. Promoted out of ship.tscn (Phase 3 Steps 19+20)
## so respawn doesn't teleport the view and non-ship scenes (intro, victory)
## can drive the camera without grafting a child onto a player node.
##
## Follows a target Node2D each physics frame (null is a valid state — camera
## holds its last position, useful during intros or victory fades). Built-in
## Camera2D position_smoothing does the lerp.
##
## Listens on Events for:
##   - screen_shake_requested(trauma) — trauma-squared offset model
##     (Eiserloh, GDC 2016), replaces ship.gd._process_camera_shake.
##   - camera_zoom_punch_requested(scale, duration) — replaces the dash
##     zoom tween that used to live in ship.gd._start_dash.

## Peak px offset at trauma=1.0. Pixel-snapped via roundf for the integer-
## scale 640x360 viewport. Matches the default in DashStats.shake_magnitude_px.
const SHAKE_MAGNITUDE_PX: float = 3.0
## Linear trauma decay per second.
const SHAKE_TRAUMA_DECAY: float = 2.0

var _target: Node2D = null
var _shake_trauma: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _zoom_tween: Tween = null


func _ready() -> void:
	_base_zoom = zoom
	Events.screen_shake_requested.connect(_on_screen_shake_requested)
	Events.camera_zoom_punch_requested.connect(_on_camera_zoom_punch_requested)


func _physics_process(_delta: float) -> void:
	# Camera2D runs in physics-process mode because the project enables
	# physics_interpolation. Follow the target on the same clock.
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position


func _process(delta: float) -> void:
	_process_shake(delta)


## Assign the Node2D the camera should follow. Passing null is valid — the
## camera keeps its last position and stops tracking.
func set_target(target: Node2D) -> void:
	_target = target


## Snap the smoothed view to the current target to avoid a one-frame rubber-
## band after a hard teleport (e.g. respawn).
func snap_to_target() -> void:
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position
	reset_smoothing()


func _on_screen_shake_requested(trauma: float) -> void:
	_shake_trauma = maxf(_shake_trauma, clampf(trauma, 0.0, 1.0))


## `scale_amount` is an absolute zoom value (e.g. 1.1 means Vector2(1.1, 1.1)),
## matching the legacy ship.gd dash tween semantics against DashStats.
## zoom_punch_target. Returns to the camera's _base_zoom after the punch.
func _on_camera_zoom_punch_requested(scale_amount: float, duration: float) -> void:
	if duration <= 0.0:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var punch_zoom: Vector2 = Vector2(scale_amount, scale_amount)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "zoom", punch_zoom, duration * 0.4)
	_zoom_tween.tween_property(self, "zoom", _base_zoom, duration * 0.6)


func _process_shake(delta: float) -> void:
	# Trauma-squared model: offset = trauma^2 * magnitude. Linear decay.
	# Writes offset (NOT position) so position_smoothing_enabled doesn't
	# swallow the shake.
	if _shake_trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_shake_trauma = maxf(0.0, _shake_trauma - SHAKE_TRAUMA_DECAY * delta)
	var amplitude: float = _shake_trauma * _shake_trauma * SHAKE_MAGNITUDE_PX
	offset = Vector2(
		roundf(randf_range(-amplitude, amplitude)),
		roundf(randf_range(-amplitude, amplitude)),
	)
