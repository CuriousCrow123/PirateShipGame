class_name MovementComponent
extends Node

## Owns thrust/turn/brake/friction motion and ram-pushback collision handling
## for a CharacterBody2D ship. Reads input from a sibling PlayerInputComponent
## and emits `rammed_enemy` so the entity root can coordinate mutual damage
## (which currently has to flow through Ship.take_damage so the iframe gating
## still lives in HealthComponent).
##
## Phase 4 Step 22: extracted from ship.gd's `_apply_normal_movement` and
## `_process_collision_pushback`. The dash branch of Ship._physics_process
## stays on Ship for now and moves into DashComponent in Step 25.
##
## Phase 5 Step 33: subscribes to ShipFSM.state_changed and derives
## `_locked` (true while DEAD) and `_enabled` (false while DASHING) from
## the FSM state. Ship root no longer toggles these manually.

signal rammed_enemy(enemy: Node, normal: Vector2)

var _body: CharacterBody2D = null
var _stats: ShipStats = null
var _input: PlayerInputComponent = null
var _fsm: ShipFSM = null
var _locked: bool = false
var _enabled: bool = true


func _ready() -> void:
	# Movement ticks every physics frame, so unlike most components this one
	# stays on. Ship root flips _enabled / _locked to gate motion during dash
	# and death respectively.
	set_physics_process(true)
	set_process(false)


func setup(body: CharacterBody2D, stats: ShipStats, input: PlayerInputComponent) -> void:
	assert(body != null, "MovementComponent.setup: body is null")
	assert(stats != null, "MovementComponent.setup: stats is null")
	assert(input != null, "MovementComponent.setup: input is null")
	_body = body
	_stats = stats
	_input = input


## Subscribe to the Ship FSM. Ship root calls this in _ready after the FSM
## node is available. Movement derives `_locked` (DEAD) and `_enabled`
## (not DASHING) from the FSM state instead of manual flag flipping.
func connect_fsm(fsm: ShipFSM) -> void:
	assert(fsm != null, "MovementComponent.connect_fsm: fsm is null")
	_fsm = fsm
	_fsm.state_changed.connect(_on_fsm_state_changed)
	_apply_state(_fsm.get_state())


func _on_fsm_state_changed(_old: int, new_state: int) -> void:
	_apply_state(new_state)


func _apply_state(state: int) -> void:
	_locked = state == ShipFSM.State.DEAD
	_enabled = state != ShipFSM.State.DASHING


func _physics_process(delta: float) -> void:
	if not _enabled or _body == null:
		return
	if _locked:
		_body.move_and_slide()
		return
	var is_braking: bool = _input.is_brake_pressed()
	if not is_braking and _input.is_thrust_pressed():
		_body.velocity += _body.transform.y * _stats.thrust * delta
	if is_braking:
		_body.velocity = _body.velocity.move_toward(Vector2.ZERO, _stats.brake_decel * delta)
	else:
		_body.velocity *= _stats.linear_drag
	var turn_input: float = _input.get_turn_axis()
	_body.rotation += turn_input * _stats.turn_speed * delta
	_body.move_and_slide()
	process_collision_pushback(1.0)


## Public so DashComponent (Step 25) can call it after its own move_and_slide
## with the dash-specific pushback scale.
func process_collision_pushback(pushback_scale: float) -> void:
	if pushback_scale <= 0.0 or _body == null:
		return
	for i: int in range(_body.get_slide_collision_count()):
		var collision: KinematicCollision2D = _body.get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is EnemyShip:
			var push: Vector2 = collision.get_normal() * 50.0 * pushback_scale
			_body.velocity += push
			# One ram damage event per frame: emit and return so the root only
			# applies damage once even if multiple slide collisions touch the
			# same enemy across physics sub-steps.
			rammed_enemy.emit(collider, collision.get_normal())
			return
