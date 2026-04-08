class_name WaterEffectsManager
extends Node

## Phase 7 Step 38 — Owns the water displacement / wake trail plumbing that
## used to live inline on main.gd. Phase 9 Step 42/43 — all direct
## displacement_stamps.spawn_* calls were replaced with bus emits
## (Events.displacement_*_requested); WaterListener is the subscriber that
## forwards to displacement_stamps. Magic numbers moved to WaterTuning.tres.
##
## Responsibilities:
##   * Wires the displacement SubViewport texture into the shared water
##     ShaderMaterial and the WaterTrail SubViewport texture into the
##     TrailSprite overlay (both at `_ready`).
##   * Per-frame: tracks the ship's position on the DisplacementViewport +
##     WaterTrail containers, updates the water material's DisplacementOrigin
##     and speed-scaled WakeTrailStrength, emits player wake ring events
##     along the trail path, iterates SpawnService's enemy list for
##     per-enemy wake ring events, and iterates the mine list for idle bob
##     displacement events.
##   * Receives `Cannonball.water_impacted` locally (via signal connection
##     set up in SpawnService), emits `displacement_impact_requested` on
##     the bus, and re-emits `Events.cannonball_water_impact(pos)` so
##     SpawnService can fan out to nearby mines. The local-then-bus split
##     is the dispatch path for Research Delta #10.

const TrailsScript: Script = preload("res://scripts/trails.gd")
const TrailWidthCurve: Curve = preload("res://resources/trail_width_curve.tres")
const TrailGradientTex: Texture2D = preload("res://textures/WaterTrailGradient.png")

@export var tuning: WaterTuning
@export var displacement_viewport: Node2D
@export var displacement_sub_viewport: SubViewport
@export var water_trail: Node2D
@export var trail_sprite: Sprite2D
@export var wake_subviewport: SubViewport
@export var player_wake_line: Line2D
@export var chunk_container: Node2D

var _ship: Ship = null
var _spawn_service: SpawnService = null
var _wake_distance: float = 0.0
var _last_wake_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	assert(tuning != null, "WaterEffects: tuning resource is null")
	assert(displacement_viewport != null, "WaterEffects: displacement_viewport is null")
	assert(displacement_sub_viewport != null, "WaterEffects: displacement_sub_viewport is null")
	assert(water_trail != null, "WaterEffects: water_trail is null")
	assert(trail_sprite != null, "WaterEffects: trail_sprite is null")
	assert(wake_subviewport != null, "WaterEffects: wake_subviewport is null")
	assert(player_wake_line != null, "WaterEffects: player_wake_line is null")
	assert(chunk_container != null, "WaterEffects: chunk_container is null")

	# Wire wake trail SubViewport texture to the TrailSprite display.
	trail_sprite.texture = wake_subviewport.get_texture()

	# Wire displacement SubViewport texture to the shared water material.
	# Intentionally shared: all water chunks use the same DisplacementMap.
	# NOT duplicated — uniform updates propagate to every chunk simultaneously.
	# Phase 6 Step 34k audit: globally-shared write intended. Same rationale
	# applies to the per-frame DisplacementOrigin / WakeTrailStrength writes
	# in _process below — one write updates every water chunk.
	var water_mat: ShaderMaterial = chunk_container.get("water_material") as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementMap", displacement_sub_viewport.get_texture())
	water_mat.set_shader_parameter("WakeTrailMap", wake_subviewport.get_texture())


func setup(ship: Ship, spawn_service: SpawnService) -> void:
	assert(ship != null, "WaterEffects.setup: ship is null")
	assert(spawn_service != null, "WaterEffects.setup: spawn_service is null")
	_ship = ship
	_spawn_service = spawn_service
	_last_wake_pos = ship.global_position


func _process(delta: float) -> void:
	if _ship == null:
		return

	# WaterTrail node still tracks the ship so the TrailSprite overlay stays
	# centered on the player. Trail rendering math itself is pivot-based
	# inside trails.gd and no longer depends on this position.
	water_trail.global_position = _ship.global_position
	displacement_viewport.global_position = _ship.global_position

	# Update the water shader's displacement origin and speed-scaled wake strength.
	var water_mat: ShaderMaterial = chunk_container.get("water_material") as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementOrigin", _ship.global_position)
	var speed_t: float = clampf(_ship.velocity.length() / tuning.wake_speed_cap, 0.0, 1.0)
	water_mat.set_shader_parameter(
		"WakeTrailStrength", lerpf(tuning.wake_strength_idle, tuning.wake_strength_max, speed_t)
	)

	# Player wake expanding rings: emit along the trail path at intervals.
	_wake_distance += _ship.global_position.distance_to(_last_wake_pos)
	_last_wake_pos = _ship.global_position
	if (
		_wake_distance >= tuning.wake_ring_spacing
		and _ship.velocity.length() > tuning.wake_ring_speed_threshold
	):
		_wake_distance = 0.0
		var wake_pos: Vector2 = _ship.global_position - _ship.transform.y * tuning.wake_ring_offset
		Events.displacement_wake_ring_requested.emit(wake_pos)

	if _spawn_service == null:
		return

	# Per-enemy wake rings — each enemy owns its own accumulator.
	for enemy: EnemyShip in _spawn_service.get_enemies():
		if not is_instance_valid(enemy) or enemy.is_destroyed():
			continue
		var traveled: float = enemy.velocity.length() * delta
		if traveled <= 0.0:
			continue
		if enemy.consume_wake_distance(traveled):
			Events.displacement_wake_ring_requested.emit(enemy.get_wake_ring_position())

	# Mine idle bob displacement.
	for mine: SeaMine in _spawn_service.get_mines():
		if mine.is_detonated():
			continue
		Events.displacement_bob_requested.emit(mine.global_position, mine.get_bob_phase())


## Local receiver for Cannonball.water_impacted (connected in SpawnService).
## Emits the displacement impact on the bus (picked up by WaterListener) and
## re-emits on the bus so SpawnService's bus subscription fans out to nearby
## mines (Research Delta #10 dispatch).
func on_cannonball_water_impact(pos: Vector2) -> void:
	Events.displacement_impact_requested.emit(
		pos, tuning.cannonball_impact_radius, tuning.cannonball_impact_duration
	)
	Events.cannonball_water_impact.emit(pos)


## Emits a mine-explosion displacement pulse on the bus. Called from
## SpawnService._on_mine_destroyed — owning the tuning lookup here keeps
## SpawnService ignorant of WaterTuning.
func on_mine_explosion(pos: Vector2) -> void:
	Events.displacement_impact_requested.emit(
		pos, tuning.mine_explosion_impact_radius, tuning.mine_explosion_impact_duration
	)


## Connected to Ship.died in main.gd. Halts the player wake line so it
## doesn't hang in the air or bridge from death to respawn position.
func on_player_died() -> void:
	player_wake_line.set_process(false)
	player_wake_line.reset_line()


## Connected to Ship.respawned in main.gd. Resets wake accumulators so the
## teleport from death position back to spawn doesn't spawn a giant ring.
func on_player_respawned() -> void:
	if _ship != null:
		_last_wake_pos = _ship.global_position
	_wake_distance = 0.0
	player_wake_line.set_process(true)


func register_enemy_wake(enemy: EnemyShip) -> void:
	var line: Line2D = Line2D.new()
	line.set_script(TrailsScript)
	line.width = 36.0
	# trails.gd duplicates this curve in _ready() to avoid shared mutation.
	# See docs/solutions/shared-resource-mutation.md
	line.width_curve = TrailWidthCurve
	line.texture = TrailGradientTex
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	# LINE_JOINT_BEVEL (not ROUND) — round joints + alpha-fade gradient render
	# direction-asymmetrically. See:
	# docs/solutions/line2d-round-joint-alpha-gradient-asymmetry.md
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	line.gradient = grad
	# Enemies move ~2.5x slower than the player (chase 50 vs thrust 120), so
	# scale up the point count to give the trail a comparable on-screen length.
	line.max_length = 220
	line.sub_viewport = wake_subviewport
	line.follow_target = enemy
	line.pivot_target = _ship
	wake_subviewport.add_child(line)
	# Stash the Line2D on the enemy so cleanup can recover it without a
	# service-side dictionary indirection.
	enemy.set_meta("wake_line", line)


func unregister_enemy_wake(enemy: EnemyShip) -> void:
	if not enemy.has_meta("wake_line"):
		return
	var line: Line2D = enemy.get_meta("wake_line") as Line2D
	enemy.remove_meta("wake_line")
	if not is_instance_valid(line):
		return
	# Fade the wake trail out instead of snap-clearing — matches the hull
	# fade duration in EnemyShip._destroy().
	line.set_process(false)
	var tween: Tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.4)
	tween.tween_callback(line.queue_free)
