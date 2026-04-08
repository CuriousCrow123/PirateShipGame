class_name PlayerInputComponent
extends Node

## Reads the Godot InputMap and exposes typed axes/buttons for the Ship root.
##
## Phase 3 Step 17: sole point of contact with `Input.*` for gameplay actions.
## System-level inputs (fullscreen, debug overlay, explosion-mode toggle)
## stay in main.gd / debug scripts — this component is player-only.
##
## No `_process` / `_physics_process` — reads are pull-based via getters so
## callers always see the freshest InputMap state and there's no one-frame lag
## between poll and consumption. Action-press edges are exposed via methods
## that forward `event.is_action_pressed()` — Ship's `_unhandled_input` calls
## those with the raw `InputEvent` so edge detection keeps working.
##
## Phase 5 Step 33: subscribes to ShipFSM.state_changed and gates all reads
## behind `_active` (false while DEAD). Replaces the legacy `_input_locked`
## flag on Ship root.

const THRUST_ACTION: StringName = &"move_forward"
const BRAKE_ACTION: StringName = &"move_back"
const TURN_LEFT_ACTION: StringName = &"turn_left"
const TURN_RIGHT_ACTION: StringName = &"turn_right"
const FIRE_PORT_ACTION: StringName = &"fire_port"
const FIRE_STARBOARD_ACTION: StringName = &"fire_starboard"
const DROP_MINE_ACTION: StringName = &"drop_mine"
const DASH_ACTION: StringName = &"dash"

var _fsm: ShipFSM = null
var _active: bool = true


func _ready() -> void:
	# Default-off per component doctrine; this component is pull-based.
	set_process(false)
	set_physics_process(false)


## Subscribe to the Ship FSM. Inputs are silently ignored while the ship
## is DEAD so the Ship root no longer needs an `_input_locked` guard.
func connect_fsm(fsm: ShipFSM) -> void:
	assert(fsm != null, "PlayerInputComponent.connect_fsm: fsm is null")
	_fsm = fsm
	_fsm.state_changed.connect(_on_fsm_state_changed)
	_active = not _fsm.is_input_locked()


func _on_fsm_state_changed(_old: int, new_state: int) -> void:
	_active = new_state != ShipFSM.State.DEAD


## -1.0 .. +1.0 turn axis (A/D on keyboard; left stick X on gamepad).
func get_turn_axis() -> float:
	if not _active:
		return 0.0
	return Input.get_axis(TURN_LEFT_ACTION, TURN_RIGHT_ACTION)


## True while the thrust button is held.
func is_thrust_pressed() -> bool:
	if not _active:
		return false
	return Input.is_action_pressed(THRUST_ACTION)


## True while the brake button is held.
func is_brake_pressed() -> bool:
	if not _active:
		return false
	return Input.is_action_pressed(BRAKE_ACTION)


## Edge detection for fire-port — pass the `_unhandled_input` event through.
func is_fire_port_just_pressed(event: InputEvent) -> bool:
	if not _active:
		return false
	return event.is_action_pressed(FIRE_PORT_ACTION)


## Edge detection for fire-starboard — pass the `_unhandled_input` event through.
func is_fire_starboard_just_pressed(event: InputEvent) -> bool:
	if not _active:
		return false
	return event.is_action_pressed(FIRE_STARBOARD_ACTION)


## Edge detection for mine drop — pass the `_unhandled_input` event through.
func is_drop_mine_just_pressed(event: InputEvent) -> bool:
	if not _active:
		return false
	return event.is_action_pressed(DROP_MINE_ACTION)


## Edge detection for dash — pass the `_unhandled_input` event through.
func is_dash_just_pressed(event: InputEvent) -> bool:
	if not _active:
		return false
	return event.is_action_pressed(DASH_ACTION)
