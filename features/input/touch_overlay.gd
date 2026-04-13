class_name TouchOverlay
extends CanvasLayer
## Shows/hides the virtual joystick and action buttons based on the
## active input mode from TouchInputManager.
##
## Call setup(ship) from main so the joystick can read the ship's heading
## for omnidirectional-feel steering.

@onready var _joystick: VirtualJoystick = $VirtualJoystick
@onready var _buttons: TouchButtonCluster = $TouchButtonCluster
@onready var _tilt: TiltSteering = $TiltSteering


func _ready() -> void:
	assert(_joystick != null, "TouchOverlay: VirtualJoystick not found")
	assert(_buttons != null, "TouchOverlay: TouchButtonCluster not found")
	assert(_tilt != null, "TouchOverlay: TiltSteering not found")

	layer = 5
	TouchInputManager.input_mode_changed.connect(_on_mode_changed)
	_apply_mode(TouchInputManager.current_mode)


## Wire the ship so the joystick and tilt can compare to ship heading.
func setup(ship: Node2D) -> void:
	_joystick.setup(ship)
	_tilt.setup(ship)


func _on_mode_changed(new_mode: int) -> void:
	_apply_mode(new_mode)


func _apply_mode(mode: int) -> void:
	var is_touch: bool = TouchInputManager.is_touch_active()
	var is_tilt: bool = mode == TouchInputManager.InputMode.TOUCH_TILT

	# Joystick only in joystick mode; tilt handles everything itself.
	_joystick.visible = is_touch and not is_tilt
	_joystick.set_process_input(is_touch and not is_tilt)
	_buttons.visible = is_touch
	_buttons.set_process_input(is_touch)
	_tilt.set_physics_process(is_tilt)

	if not is_touch:
		Input.action_release("turn_left")
		Input.action_release("turn_right")
		Input.action_release("move_forward")
		Input.action_release("move_back")
