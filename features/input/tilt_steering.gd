class_name TiltSteering
extends Node
## Reads device accelerometer and uses heading-based mapping: the tilt
## direction is the desired heading, and the script auto-steers + auto-
## thrusts toward it — same feel as the virtual joystick.
##
## Call setup(ship) so the node can compare tilt angle to ship heading.
##
## On desktop debug builds, mouse offset from screen centre simulates
## tilt so the feature can be tested without a physical device.

## Angle within which the ship is "close enough" for full thrust.
const ALIGN_CONE: float = PI * 0.35
## Beyond this the stick/tilt is treated as reverse → brake.
const REVERSE_CONE: float = PI * 0.75

@export var sensitivity: float = 5.0
@export var deadzone: float = 1.0

var _target: Node2D = null


func _ready() -> void:
	set_physics_process(false)


func setup(target: Node2D) -> void:
	_target = target


func _physics_process(_delta: float) -> void:
	var tilt: Vector2 = _read_tilt_2d()
	var magnitude: float = tilt.length()

	if magnitude < deadzone:
		Input.action_release("turn_left")
		Input.action_release("turn_right")
		Input.action_release("move_forward")
		Input.action_release("move_back")
		return

	var norm_mag: float = clampf((magnitude - deadzone) / (sensitivity - deadzone), 0.0, 1.0)

	if _target == null:
		_inject_turn_only(tilt, norm_mag)
		return

	_inject_heading(tilt, norm_mag)


## Heading-based: tilt direction = desired heading, auto-steer + thrust.
func _inject_heading(tilt: Vector2, magnitude: float) -> void:
	# Map tilt vector to a screen-space direction. Accelerometer X = right
	# tilt, Y = forward tilt (toward top of device). Screen-space: right
	# = +X, down = +Y. So tilt-forward (accel +Y) maps to screen-up (-Y).
	var desired_dir: Vector2 = Vector2(tilt.x, -tilt.y)
	var desired_angle: float = desired_dir.angle()

	# Ship forward = transform.y (see movement_component.gd line 72).
	var ship_forward: Vector2 = _target.transform.y
	var ship_angle: float = ship_forward.angle()
	var angle_delta: float = angle_difference(ship_angle, desired_angle)

	# --- Steering ---
	var abs_delta: float = absf(angle_delta)
	if abs_delta > 0.08:
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
		Input.action_press("move_back", magnitude)
		Input.action_release("move_forward")
	elif abs_delta < ALIGN_CONE:
		Input.action_press("move_forward", magnitude)
		Input.action_release("move_back")
	else:
		var align_factor: float = 1.0 - (abs_delta - ALIGN_CONE) / (REVERSE_CONE - ALIGN_CONE)
		var thrust_str: float = align_factor * magnitude
		if thrust_str > 0.05:
			Input.action_press("move_forward", thrust_str)
			Input.action_release("move_back")
		else:
			Input.action_release("move_forward")
			Input.action_release("move_back")


## Fallback when no target is set: turn only (no thrust from tilt).
func _inject_turn_only(tilt: Vector2, magnitude: float) -> void:
	if tilt.x > 0.0:
		Input.action_press("turn_right", magnitude)
		Input.action_release("turn_left")
	else:
		Input.action_press("turn_left", magnitude)
		Input.action_release("turn_right")


## Returns a 2D tilt vector from the accelerometer (X = right, Y = forward).
func _read_tilt_2d() -> Vector2:
	var accel: Vector3 = Input.get_accelerometer()
	if accel != Vector3.ZERO:
		return Vector2(accel.x, accel.y)
	# Desktop debug: simulate tilt from mouse offset from centre.
	if OS.is_debug_build():
		var vp: Viewport = get_viewport()
		if vp == null:
			return Vector2.ZERO
		var center: Vector2 = vp.get_visible_rect().size * 0.5
		var mouse: Vector2 = vp.get_mouse_position()
		var offset: Vector2 = mouse - center
		return offset / center.x * sensitivity
	return Vector2.ZERO
