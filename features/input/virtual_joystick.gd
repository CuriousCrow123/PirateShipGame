class_name VirtualJoystick
extends Control
## Touch-driven analog stick rendered via _draw(). Uses heading-based
## mapping: the stick direction is the DESIRED heading, and the script
## auto-steers + auto-thrusts toward it. This feels omnidirectional to
## the player even though the ship only has forward thrust, brake, and
## rotation.
##
## Requires a target Node2D (the ship) so it can compare the stick angle
## to the ship's current facing. Call setup() from the parent overlay.
##
## In tilt_only_mode the horizontal axis is ignored (tilt handles
## steering) and the vertical axis maps directly to thrust/brake.

const BASE_COLOR: Color = Color(0.9, 0.88, 0.78, 0.25)
const KNOB_COLOR: Color = Color(0.95, 0.85, 0.55, 0.5)
const BASE_RADIUS: float = 36.0
const KNOB_RADIUS: float = 14.0

## Angle (radians) within which the ship is "close enough" to the target
## heading and full thrust is applied. Outside this cone thrust is scaled
## down so the ship prioritises rotating before speeding off sideways.
const ALIGN_CONE: float = PI * 0.35
## Beyond this angle delta the stick is treated as "pull backwards" and
## the ship brakes instead of thrusting.
const REVERSE_CONE: float = PI * 0.75

@export var deadzone: float = 0.15
@export var stick_radius: float = 36.0

## When true only the Y-axis (thrust/brake) is processed. Used in
## TOUCH_TILT mode where the accelerometer handles turning.
var tilt_only_mode: bool = false

var _target: Node2D = null
var _touch_index: int = -1
var _base_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func setup(target: Node2D) -> void:
	_target = target


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	var drag: InputEventScreenDrag = event as InputEventScreenDrag

	if touch != null:
		_handle_touch(touch)
	elif drag != null and drag.index == _touch_index:
		_handle_drag(drag)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index != -1:
			return
		var vp_pos: Vector2 = _to_viewport_pos(event.position)
		var vp_size: Vector2 = get_viewport_rect().size
		if vp_pos.x > vp_size.x * 0.5:
			return
		_touch_index = event.index
		_base_center = vp_pos
		_knob_offset = Vector2.ZERO
		_active = true
		queue_redraw()
	else:
		if event.index != _touch_index:
			return
		_release()


func _handle_drag(event: InputEventScreenDrag) -> void:
	var vp_pos: Vector2 = _to_viewport_pos(event.position)
	var offset: Vector2 = vp_pos - _base_center
	if offset.length() > stick_radius:
		offset = offset.normalized() * stick_radius
	_knob_offset = offset
	_inject_input()
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_active = false
	_knob_offset = Vector2.ZERO
	Input.action_release("turn_left")
	Input.action_release("turn_right")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	queue_redraw()


func _inject_input() -> void:
	var normalized: Vector2 = _knob_offset / stick_radius
	var magnitude: float = normalized.length()
	if magnitude < deadzone:
		Input.action_release("turn_left")
		Input.action_release("turn_right")
		Input.action_release("move_forward")
		Input.action_release("move_back")
		return

	if tilt_only_mode:
		_inject_tilt_only(normalized)
		return

	if _target == null:
		_inject_direct(normalized)
		return

	_inject_heading(normalized, magnitude)


## Heading-based: stick direction = desired heading, auto-steer + thrust.
func _inject_heading(normalized: Vector2, magnitude: float) -> void:
	# Desired heading from stick (screen-space: up = -Y).
	var desired_angle: float = Vector2(normalized.x, normalized.y).angle()
	# Ship thrusts along transform.y (see movement_component.gd line 72:
	# velocity += transform.y * thrust). thrust is positive (120), so the
	# ship's forward direction IS transform.y, not its negation.
	var ship_forward: Vector2 = _target.transform.y
	var ship_angle: float = ship_forward.angle()
	var angle_delta: float = angle_difference(ship_angle, desired_angle)

	# --- Steering ---
	var abs_delta: float = absf(angle_delta)
	if abs_delta > deadzone * 0.5:
		var turn_strength: float = clampf(abs_delta / ALIGN_CONE, 0.0, 1.0)
		if angle_delta > 0.0:
			Input.action_press("turn_right", turn_strength)
			Input.action_release("turn_left")
		else:
			Input.action_press("turn_left", turn_strength)
			Input.action_release("turn_right")
	else:
		Input.action_release("turn_left")
		Input.action_release("turn_right")

	# --- Thrust / brake ---
	if abs_delta > REVERSE_CONE:
		# Stick is roughly opposite the ship's heading → brake.
		var brake_str: float = (magnitude - deadzone) / (1.0 - deadzone)
		Input.action_press("move_back", brake_str)
		Input.action_release("move_forward")
	elif abs_delta < ALIGN_CONE:
		# Well-aligned → full thrust proportional to stick magnitude.
		var thrust_str: float = (magnitude - deadzone) / (1.0 - deadzone)
		Input.action_press("move_forward", thrust_str)
		Input.action_release("move_back")
	else:
		# In between: partial thrust that ramps down as misalignment grows.
		var align_factor: float = 1.0 - (abs_delta - ALIGN_CONE) / (REVERSE_CONE - ALIGN_CONE)
		var thrust_str: float = align_factor * (magnitude - deadzone) / (1.0 - deadzone)
		if thrust_str > 0.05:
			Input.action_press("move_forward", thrust_str)
			Input.action_release("move_back")
		else:
			Input.action_release("move_forward")
			Input.action_release("move_back")


## Fallback when no target is set: direct axis mapping.
func _inject_direct(normalized: Vector2) -> void:
	if absf(normalized.x) > deadzone:
		var strength: float = (absf(normalized.x) - deadzone) / (1.0 - deadzone)
		if normalized.x < 0.0:
			Input.action_press("turn_left", strength)
			Input.action_release("turn_right")
		else:
			Input.action_press("turn_right", strength)
			Input.action_release("turn_left")
	else:
		Input.action_release("turn_left")
		Input.action_release("turn_right")

	_inject_vertical(normalized)


## Tilt mode: only vertical axis (thrust/brake), tilt handles turn.
func _inject_tilt_only(normalized: Vector2) -> void:
	_inject_vertical(normalized)


## Shared vertical-axis logic for direct and tilt modes.
func _inject_vertical(normalized: Vector2) -> void:
	if absf(normalized.y) > deadzone:
		var strength: float = (absf(normalized.y) - deadzone) / (1.0 - deadzone)
		if normalized.y < 0.0:
			Input.action_press("move_forward", strength)
			Input.action_release("move_back")
		else:
			Input.action_press("move_back", strength)
			Input.action_release("move_forward")
	else:
		Input.action_release("move_forward")
		Input.action_release("move_back")


func _draw() -> void:
	if not _active:
		return
	draw_circle(_base_center, BASE_RADIUS, BASE_COLOR)
	draw_arc(_base_center, BASE_RADIUS, 0.0, TAU, 32, KNOB_COLOR, 1.5)
	draw_circle(_base_center + _knob_offset, KNOB_RADIUS, KNOB_COLOR)


func _to_viewport_pos(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_screen_transform().affine_inverse() * screen_pos
