class_name EnemyAIMovement
extends Node

## Phase 8 Step 40 — Bespoke movement component for the chase-and-circle
## enemy AI extracted from enemy_ship.gd. Single strategy for now (no
## inheritance hierarchy or strategy table) per the brainstorm's YAGNI
## gate: a second archetype is the trigger to add a strategy interface.
##
## Drives a CharacterBody2D toward an injected target. When far from the
## target, steers directly (chase). When inside `circle_radius`, steers
## perpendicular for broadside orbiting. Each physics tick it also checks
## broadside alignment + range against the target and emits
## `broadside_fire_requested(starboard)` so the entity root can drive
## BroadsideComponent. Cooldown gating lives on BroadsideComponent — this
## component just signals "the geometry is right, try to fire."
##
## Subscribes to ShipFSM.state_changed and freezes (zero velocity, no
## steering, no fire request) while the entity is DEAD. Wave modifiers
## are applied via `apply_wave_modifiers(speed_mult)`.

signal broadside_fire_requested(starboard: bool)

const BROADSIDE_ALIGNMENT_THRESHOLD: float = 0.85

var _body: CharacterBody2D = null
var _target: Node2D = null
var _fsm: ShipFSM = null
var _chase_speed: float = 50.0
var _circle_speed: float = 40.0
var _turn_speed: float = 2.0
var _circle_radius: float = 120.0
var _broadside_range: float = 130.0
var _locked: bool = false


func _ready() -> void:
	set_process(false)
	# Movement ticks every physics frame; the enemy root no longer drives
	# this from its own _physics_process.
	set_physics_process(true)


func setup(body: CharacterBody2D, archetype: EnemyArchetype) -> void:
	assert(body != null, "EnemyAIMovement.setup: body is null")
	assert(archetype != null, "EnemyAIMovement.setup: archetype is null")
	_body = body
	_chase_speed = archetype.chase_speed
	_circle_speed = archetype.circle_speed
	_turn_speed = archetype.turn_speed
	_circle_radius = archetype.circle_radius
	_broadside_range = archetype.broadside_range


func set_target(target: Node2D) -> void:
	_target = target


func connect_fsm(fsm: ShipFSM) -> void:
	assert(fsm != null, "EnemyAIMovement.connect_fsm: fsm is null")
	_fsm = fsm
	_fsm.state_changed.connect(_on_fsm_state_changed)
	_locked = _fsm.is_dead()


func apply_wave_modifiers(speed_mult: float) -> void:
	## Per-wave difficulty scaling. Multiplies BOTH chase and circle speed.
	## Cooldown scaling lives on BroadsideComponent's `fire_rate_mult`.
	_chase_speed *= speed_mult
	_circle_speed *= speed_mult


func _on_fsm_state_changed(_old: int, new_state: int) -> void:
	_locked = new_state == ShipFSM.State.DEAD
	if _locked and _body != null:
		_body.velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if _body == null or _body.is_queued_for_deletion():
		return
	if _locked:
		_body.move_and_slide()
		return
	if _target != null and is_instance_valid(_target):
		_steer_toward_target(delta)
		_check_broadside_alignment()
	_body.move_and_slide()


func _steer_toward_target(delta: float) -> void:
	var to_target: Vector2 = _target.global_position - _body.global_position
	var dist: float = to_target.length()
	var desired_dir: Vector2

	if dist > _circle_radius:
		# Chase: steer directly toward the player.
		desired_dir = to_target.normalized()
	else:
		# Circle: steer perpendicular (clockwise) for broadside orbiting.
		desired_dir = Vector2(to_target.y, -to_target.x).normalized()

	# Smoothly rotate toward desired heading (-transform.y is forward).
	var forward: Vector2 = -_body.transform.y
	var desired_angle: float = desired_dir.angle()
	var current_angle: float = forward.angle()
	var angle_diff: float = wrapf(desired_angle - current_angle, -PI, PI)
	_body.rotation += clampf(angle_diff, -_turn_speed * delta, _turn_speed * delta)

	# Speed: full chase speed when far, circle speed when orbiting.
	var speed: float = _chase_speed if dist > _circle_radius else _circle_speed
	_body.velocity = -_body.transform.y * speed


func _check_broadside_alignment() -> void:
	var to_target: Vector2 = _target.global_position - _body.global_position
	var dist: float = to_target.length()
	if dist > _broadside_range or dist < 0.001:
		return
	var dir_to_target: Vector2 = to_target / dist
	# Ship right (starboard) is +transform.x; left (port) is -transform.x.
	# transform.x has length == scale.x (0.5), so normalize before the dot
	# or the threshold (0.85) is unreachable.
	var starboard: Vector2 = _body.transform.x.normalized()
	var dot: float = starboard.dot(dir_to_target)
	if dot >= BROADSIDE_ALIGNMENT_THRESHOLD:
		broadside_fire_requested.emit(true)
	elif dot <= -BROADSIDE_ALIGNMENT_THRESHOLD:
		broadside_fire_requested.emit(false)
