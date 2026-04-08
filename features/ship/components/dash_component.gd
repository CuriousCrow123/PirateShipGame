class_name DashComponent
extends Node

## Owns the dash impulse, dash-window physics, dash cooldown, the ghost
## trail spawning loop, freeze-frame / time-dip Engine.time_scale writes,
## and the defensive time_scale reset on _exit_tree. Drives the dash fire
## effect on/off.
##
## Phase 4 Step 25: extracted from ship.gd. GhostTrailComponent (A2) is
## fused into this component per Appendix A.
##
## Phase 6 Step 34b/c documented exception: the freeze-frame and time-dip
## timers stay as raw `get_tree().create_timer(seconds, true, false, true)`
## lambdas (process_always=true, ignore_time_scale=true). The generic
## `Cooldown` helper is wall-clock based too, BUT its natural consumption
## pattern is polling in _process — and _physics_process / _process ticks
## halt while `Engine.time_scale = 0`, so a polled Cooldown would never fire
## during a freeze. SceneTreeTimer.timeout is an autoload-scope signal
## dispatched by the SceneTree's always-loop; the connected lambda fires
## regardless of this component's process_mode or pause state, so there is
## no need to set PROCESS_MODE_ALWAYS here. The dash cooldown (34d) is a
## normal gameplay cooldown and does use the Cooldown helper below.
##
## During dash, the ship body's MovementComponent is disabled via Ship root
## (Ship listens to dash_started/dash_ended) so this component is the sole
## driver of the body's velocity and rotation while a burst is active.

signal dash_started
signal dash_ended

var dash_stats: DashStats = null

var _body: CharacterBody2D = null
var _input: PlayerInputComponent = null
var _fire_effect: DashFireEffect = null
var _ghost_sources: Array[Sprite2D] = []
var _ghost_container: Node2D = null
var _ghost_additive_material: CanvasItemMaterial = null

var _cooldown: Cooldown = Cooldown.new()
var _is_active: bool = false
var _remaining: float = 0.0
var _next_ghost_in: float = 0.0


func _ready() -> void:
	# Default off — we tick our own _physics_process / _process only while
	# a dash burst is active.
	set_physics_process(false)
	set_process(false)
	# Cached additive material reused across all ghost spawns. Godot does
	# NOT fork CanvasItemMaterial on assignment — all ghosts share the same
	# RID and batch together.
	_ghost_additive_material = CanvasItemMaterial.new()
	_ghost_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


## Wired by the entity root in its own _ready (after children).
func setup(
	body: CharacterBody2D,
	stats: DashStats,
	input: PlayerInputComponent,
	fire_effect: DashFireEffect,
	ghost_sources: Array[Sprite2D],
	ghost_container: Node2D
) -> void:
	assert(body != null, "DashComponent.setup: body is null")
	assert(stats != null, "DashComponent.setup: dash_stats is null")
	assert(input != null, "DashComponent.setup: input is null")
	assert(fire_effect != null, "DashComponent.setup: fire_effect is null")
	_body = body
	dash_stats = stats
	_input = input
	_fire_effect = fire_effect
	_ghost_sources = ghost_sources
	_ghost_container = ghost_container


func _exit_tree() -> void:
	# Defensive: if a freeze/dip lambda failed mid-burst (freed instance,
	# etc.), make sure we never leave the engine in scaled time when this
	# component's owner leaves the tree. (Research Delta #9.)
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0


func is_active() -> bool:
	return _is_active


## Returns true if the dash actually started.
func try_start() -> bool:
	if not _cooldown.is_ready() or _is_active:
		return false
	_is_active = true
	_remaining = dash_stats.duration
	# Apply initial impulse based on feel mode.
	match dash_stats.feel_mode:
		DashStats.FeelMode.VELOCITY_ALIGNED:
			if _body.velocity.length() < 1.0:
				_body.velocity += _body.transform.y * dash_stats.impulse_speed
			else:
				_body.velocity += _body.velocity.normalized() * dash_stats.impulse_speed
		_:
			# Dash has three behaviors at once:
			# - Forward component is kept (so dashing while already moving
			#   forward stacks → actually goes faster).
			# - Backward component is discarded (reverse dash = clean reset,
			#   not an anemic trickle fighting prior momentum).
			# - Perpendicular component is discarded (sharp turn-dashes
			#   don't get dragged sideways by prior drift).
			var forward: Vector2 = _body.transform.y
			var kept_forward_speed: float = maxf(_body.velocity.dot(forward), 0.0)
			_body.velocity = forward * (kept_forward_speed + dash_stats.impulse_speed)
	# Push current fire-config uniforms onto the 3D effect and start emitting.
	_fire_effect.start(dash_stats)
	# Reset ghost spawn timer so the first ghost spawns next render tick.
	_next_ghost_in = 0.0
	# Bump shake trauma via the bus — GameCamera owns the shake state now.
	Events.screen_shake_requested.emit(dash_stats.shake_trauma_initial)
	# Optional zoom punch — GameCamera's bus listener tweens its own zoom.
	if dash_stats.zoom_punch_duration > 0.0:
		Events.camera_zoom_punch_requested.emit(
			dash_stats.zoom_punch_target, dash_stats.zoom_punch_duration
		)
	# Optional Celeste-style freeze frames at burst start.
	if dash_stats.freeze_frames > 0:
		var freeze_seconds: float = float(dash_stats.freeze_frames) / 60.0
		Engine.time_scale = 0.0
		# process_always=true, ignore_time_scale=true so the timer fires in
		# real time even with Engine.time_scale = 0.
		get_tree().create_timer(freeze_seconds, true, false, true).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					Engine.time_scale = 1.0
		)
	# Optional time-scale dip (mutually exclusive in practice with freeze;
	# if both are set, freeze wins because it sets time_scale = 0 first).
	elif dash_stats.time_dip_value < 1.0 and dash_stats.time_dip_duration > 0.0:
		Engine.time_scale = dash_stats.time_dip_value
		get_tree().create_timer(dash_stats.time_dip_duration, true, false, true).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					Engine.time_scale = 1.0
		)
	# Phase 6 Step 34d: gameplay cooldown uses the wall-clock Cooldown helper.
	# `try_start()` polls `_cooldown.is_ready()` on the next input attempt —
	# no per-frame poll needed.
	_cooldown.start(dash_stats.cooldown)
	set_physics_process(true)
	set_process(true)
	dash_started.emit()
	return true


## Force-stop the dash (e.g. on death). Idempotent.
func stop() -> void:
	if not _is_active:
		return
	_end_dash()


func _physics_process(delta: float) -> void:
	if not _is_active or _body == null:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_end_dash()
		return
	var is_braking: bool = _input.is_brake_pressed()
	var turn_input: float = _input.get_turn_axis()
	var stats: ShipStats = (_body as Ship).stats
	match dash_stats.feel_mode:
		DashStats.FeelMode.LOCKED_HEADING:
			_body.velocity *= stats.linear_drag
		DashStats.FeelMode.STEERABLE:
			if not is_braking and _input.is_thrust_pressed():
				_body.velocity += _body.transform.y * stats.thrust * delta
			_body.velocity *= stats.linear_drag
			_body.rotation += turn_input * stats.turn_speed * delta
		DashStats.FeelMode.VELOCITY_ALIGNED:
			_body.velocity *= stats.linear_drag
			_body.rotation += turn_input * stats.turn_speed * delta
		DashStats.FeelMode.OVERSPEED_CAP:
			if not is_braking and _input.is_thrust_pressed():
				_body.velocity += _body.transform.y * stats.thrust * delta
			_body.velocity *= dash_stats.overspeed_drag
			_body.rotation += turn_input * stats.turn_speed * delta
	_body.move_and_slide()
	# Ram pushback during dash uses the dash-specific scale. The Ship root
	# wired MovementComponent.rammed_enemy at startup; the same handler
	# applies because dash collisions still go through MovementComponent's
	# helper.
	var movement: MovementComponent = (_body as Ship).get_node("Movement") as MovementComponent
	movement.process_collision_pushback(dash_stats.collision_pushback_scale)


func _process(delta: float) -> void:
	if not _is_active:
		return
	var t: float = 1.0 - clampf(_remaining / dash_stats.duration, 0.0, 1.0)
	var dash_strength: float = 1.0
	if dash_stats.intensity_curve != null:
		dash_strength = dash_stats.intensity_curve.sample_baked(t)
	_fire_effect.set_dash_strength(dash_strength)
	if dash_stats.ghost_count > 0:
		_next_ghost_in -= delta
		if _next_ghost_in <= 0.0:
			_spawn_ghost()
			_next_ghost_in = dash_stats.ghost_spawn_interval


func _spawn_ghost() -> void:
	if _ghost_container == null:
		return
	for src: Sprite2D in _ghost_sources:
		if src == null:
			continue
		var ghost: Sprite2D = Sprite2D.new()
		ghost.texture = src.texture
		ghost.region_enabled = src.region_enabled
		ghost.region_rect = src.region_rect
		ghost.centered = src.centered
		ghost.offset = src.offset
		ghost.global_transform = src.global_transform
		ghost.modulate = dash_stats.ghost_start_tint
		# Render ghosts above the ship (ship.z_index = 2). Absolute z since
		# the ghost is reparented to the world container, not the ship.
		ghost.z_as_relative = false
		ghost.z_index = 10
		if dash_stats.ghost_additive:
			ghost.material = _ghost_additive_material
		_ghost_container.add_child(ghost)
		var tw: Tween = ghost.create_tween()
		tw.tween_property(
			ghost, "modulate", dash_stats.ghost_end_tint, dash_stats.ghost_fade_duration
		)
		tw.tween_callback(ghost.queue_free)


func _end_dash() -> void:
	_is_active = false
	_remaining = 0.0
	# Effect resets DashStrength to 0 internally and schedules SubViewport
	# shutdown after particles fully die. In-flight particles still drift
	# and fade naturally during the tail.
	_fire_effect.stop()
	# Defensive: if a dip lambda hasn't fired yet (or won't), restore time
	# scale here so a stalled dip can't outlive the burst.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
	set_physics_process(false)
	set_process(false)
	dash_ended.emit()
