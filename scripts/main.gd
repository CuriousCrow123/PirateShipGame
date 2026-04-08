extends Node2D
## Scene root — wires the displacement SubViewport to the water shader,
## keeps the displacement viewport tracking the ship, spawns cannonballs,
## and manages enemy ship spawning/despawning, wake trails, and displacement.

enum WavePhase { INTERMISSION, SPAWNING, CLEARING, ENDED }

const CannonballScene: PackedScene = preload("res://scenes/cannonball.tscn")
const EnemyShipScene: PackedScene = preload("res://scenes/enemy_ship.tscn")
const SeaMineScene: PackedScene = preload("res://scenes/sea_mine.tscn")
const TrailsScript: Script = preload("res://scripts/trails.gd")
const TrailWidthCurve: Curve = preload("res://resources/trail_width_curve.tres")
const TrailGradientTex: Texture2D = preload("res://textures/WaterTrailGradient.png")

# Wave progression is now driven by a WaveSet Resource (Phase 2 Step 14).
# The procedural formula constants that used to live here have moved into
# resources/waves/wave_NN.tres. WAVE_TOAST_LEAD_TIME stays here because it's
# a UI lead-time, not a difficulty curve point.
const WAVE_TOAST_LEAD_TIME: float = 1.5

@export var wave_set: WaveSet
@export var spawn_distance: float = 550.0
@export var despawn_distance: float = 1000.0

var _enemies: Array[EnemyShip] = []
var _mines: Array[SeaMine] = []
var _wake_distance: float = 0.0
var _last_wake_pos: Vector2 = Vector2.ZERO

# Wave state.
var _current_wave: int = 0
var _wave_phase: WavePhase = WavePhase.INTERMISSION
var _intermission_timer: float = 4.0  # overwritten from WaveConfig in _ready
var _toast_shown_for_wave: int = 0
var _enemies_spawned_this_wave: int = 0
var _enemies_to_spawn_this_wave: int = 0
var _spawn_cadence_timer: float = 0.0
var _stats: RunStats = null

# Phase 6 Step 34h: game-over grace replaces the old
# `await get_tree().create_timer(1.0).timeout` with a polled Cooldown so the
# scheduler isn't holding a SceneTreeTimer reference past a scene unload.
var _run_end_cooldown: Cooldown = Cooldown.new()
var _run_end_pending: bool = false
var _run_end_stats: RunStats = null
var _run_end_victory: bool = false

@onready var _ship: Ship = $Ship
@onready var _minimap_display: MinimapDisplay = $Minimap/MinimapDisplay
@onready var _displacement_vp: SubViewport = $DisplacementViewport/SubViewport
@onready var _displacement_stamps: Node2D = $DisplacementViewport/SubViewport/Stamps
@onready var _wake_subviewport: SubViewport = $WaterTrail/SubViewport
@onready var _player_wake_line: Line2D = $WaterTrail/SubViewport/Line2D
@onready var _hp_display: HPDisplay = $HPDisplay
@onready var _wave_toast: WaveToast = $WaveToast
@onready var _lives_display: LivesDisplay = $LivesDisplay
@onready var _game_over_screen: GameOverScreen = $GameOverScreen
@onready var _victory_screen: GameOverScreen = $VictoryScreen
@onready var _mine_cooldown_display: MineCooldownDisplay = $MineCooldownDisplay
@onready var _camera: GameCamera = $GameCamera


func _ready() -> void:
	assert(_ship != null, "Main: Ship node is missing")
	assert(_minimap_display != null, "Main: MinimapDisplay node not found")
	assert(_displacement_vp != null, "Main: DisplacementViewport/SubViewport not found")
	assert(_displacement_stamps != null, "Main: Stamps node not found")
	assert(_wake_subviewport != null, "Main: WaterTrail/SubViewport not found")
	assert(_player_wake_line != null, "Main: WaterTrail/SubViewport/Line2D not found")
	assert(_hp_display != null, "Main: HPDisplay not found")
	assert(_wave_toast != null, "Main: WaveToast not found")
	assert(_lives_display != null, "Main: LivesDisplay not found")
	assert(_game_over_screen != null, "Main: GameOverScreen not found")
	assert(_victory_screen != null, "Main: VictoryScreen not found")
	assert(_mine_cooldown_display != null, "Main: MineCooldownDisplay not found")
	assert(_camera != null, "Main: GameCamera not found")
	assert(wave_set != null, "Main: wave_set (WaveSet) Resource is missing")
	# Seed the first intermission timer from the WaveSet's first wave so the
	# value is data-driven from frame 0.
	_intermission_timer = wave_set.get_wave(0).intermission_duration

	_stats = RunStats.new()

	# Wire wake trail SubViewport texture to the TrailSprite display.
	$WaterTrail/TrailSprite.texture = _wake_subviewport.get_texture()

	# Wire displacement SubViewport texture to the shared water material.
	# Intentionally shared: all water chunks use the same DisplacementMap.
	# NOT duplicated — uniform updates propagate to every chunk simultaneously.
	# Phase 6 Step 34k audit: globally-shared write intended. Same rationale
	# applies to the per-frame DisplacementOrigin / WakeTrailStrength writes
	# in _process below — one write updates every water chunk.
	var water_mat: ShaderMaterial = $ChunkContainer.water_material as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementMap", _displacement_vp.get_texture())
	water_mat.set_shader_parameter("WakeTrailMap", _wake_subviewport.get_texture())

	_last_wake_pos = _ship.global_position
	_ship.cannon_fired.connect(_on_cannon_fired)
	_ship.mine_dropped.connect(_on_mine_dropped)
	_ship.died.connect(_on_ship_died)
	_ship.respawned.connect(_on_ship_respawned)
	_ship.game_over.connect(_on_game_over)
	_ship.invincibility_changed.connect(_on_invincibility_changed)
	Events.run_ended.connect(_on_run_ended)
	_minimap_display.setup(_ship)
	_hp_display.setup(_ship)
	_lives_display.setup(_ship)
	_mine_cooldown_display.setup(_ship)
	# Defer camera target injection: Ship's _ready has already run by the time
	# Main._ready fires, but deferring keeps the contract explicit that the
	# camera accepts target injection after-the-fact and handles null cleanly.
	_camera.call_deferred("set_target", _ship)


func _process(delta: float) -> void:
	_tick_run_end_grace()

	# WaterTrail node still tracks the ship so the TrailSprite overlay stays
	# centered on the player. Trail rendering math itself is now pivot-based
	# inside trails.gd and no longer depends on this position.
	$WaterTrail.global_position = _ship.global_position

	# Displacement viewport follows ship position so stamps stay centered.
	$DisplacementViewport.global_position = _ship.global_position

	# Update the water shader's displacement origin and speed-scaled wake strength.
	var water_mat: ShaderMaterial = $ChunkContainer.water_material as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementOrigin", _ship.global_position)
	var speed_t: float = clampf(_ship.velocity.length() / 120.0, 0.0, 1.0)
	water_mat.set_shader_parameter("WakeTrailStrength", lerpf(2.0, 10.0, speed_t))

	# Player wake expanding rings: spawn along the trail path at intervals
	_wake_distance += _ship.global_position.distance_to(_last_wake_pos)
	_last_wake_pos = _ship.global_position
	if _wake_distance >= 16.0 and _ship.velocity.length() > 5.0:
		_wake_distance = 0.0
		var wake_pos: Vector2 = _ship.global_position - _ship.transform.y * 12.0
		_displacement_stamps.spawn_wake_ring(wake_pos)

	# Per-enemy wake rings — each enemy owns its own accumulator.
	for enemy: EnemyShip in _enemies:
		if not is_instance_valid(enemy) or enemy.is_destroyed():
			continue
		var traveled: float = enemy.velocity.length() * delta
		if traveled <= 0.0:
			continue
		if enemy.consume_wake_distance(traveled):
			_displacement_stamps.spawn_wake_ring(enemy.get_wake_ring_position())

	# Mine idle bob displacement
	for mine: SeaMine in _mines:
		if mine.is_detonated():
			continue
		_displacement_stamps.spawn_bob(mine.global_position, mine.get_bob_phase())


func _physics_process(delta: float) -> void:
	_update_wave_state(delta)
	_despawn_distant_enemies()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	# Toggle explosion rendering between pre-baked sprites and real-time 3D.
	if event.is_action_pressed("toggle_explosion_mode"):
		ExplosionSprite.use_sprite = not ExplosionSprite.use_sprite
		print("Explosions: ", "sprite" if ExplosionSprite.use_sprite else "3D")


func _on_ship_died() -> void:
	# Stop the wake trail and clear its point queue so the line doesn't
	# hang in the air while the ship is hidden, and doesn't bridge from
	# the death position to the respawn position on the next frame.
	_player_wake_line.set_process(false)
	_player_wake_line.reset_line()


func _on_ship_respawned() -> void:
	# Reset wake-ring distance accumulation so the teleport from death
	# position back to spawn position doesn't spawn a giant ring.
	_last_wake_pos = _ship.global_position
	_wake_distance = 0.0
	_player_wake_line.set_process(true)
	# Snap the camera to the respawn position so position_smoothing doesn't
	# rubber-band the view back from the death location.
	_camera.snap_to_target()


func _on_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	var ball: Cannonball = CannonballScene.instantiate()
	ball.water_impacted.connect(_on_cannonball_water_impacted)
	ball.hit_registered.connect(_on_player_ball_hit)
	add_child(ball)
	ball.setup(pos, dir, false)
	_stats.register_shot_fired()
	ExplosionSprite.create(self, pos, "muzzle_flash", dir, _ship.velocity * 0.75)


func _on_player_ball_hit() -> void:
	_stats.register_shot_hit()


func _on_enemy_destroyed(_enemy: EnemyShip, by_mine: bool) -> void:
	_stats.register_enemy_destroyed(by_mine)


func _on_invincibility_changed(active: bool) -> void:
	var subtitle: String = "CHEAT"
	var title: String = "INVINCIBLE ON" if active else "INVINCIBLE OFF"
	_wave_toast.show_message(subtitle, title)


func _on_game_over() -> void:
	# Guard against a victory→death race: if the last wave already cleared
	# and we're waiting on the 1s grace timer, swallow the death.
	if _wave_phase == WavePhase.ENDED:
		return
	# The in-progress wave is intentionally NOT closed out — only fully
	# completed waves get a row in the stats list. Halt wave progression so
	# no new enemies spawn between death and the run_ended route.
	_wave_phase = WavePhase.ENDED
	Events.run_ended.emit(_stats, false)


func _on_run_ended(stats: RunStats, victory: bool) -> void:
	# Short grace so the death explosion + HP drain (or final-wave clear
	# flourish) reads before the panel slides in. Phase 6 Step 34h: grace
	# timer replaced with a Cooldown polled in _process.
	_run_end_stats = stats
	_run_end_victory = victory
	_run_end_pending = true
	_run_end_cooldown.start(1.0)


func _tick_run_end_grace() -> void:
	if not _run_end_pending or not _run_end_cooldown.is_ready():
		return
	_run_end_pending = false
	if _run_end_victory:
		if is_instance_valid(_victory_screen):
			_victory_screen.show_results(_run_end_stats, true)
	else:
		if is_instance_valid(_game_over_screen):
			_game_over_screen.show_results(_run_end_stats, false)
	_run_end_stats = null


func _on_enemy_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	var ball: Cannonball = CannonballScene.instantiate()
	ball.water_impacted.connect(_on_cannonball_water_impacted)
	add_child(ball)
	# add_child must precede setup so _ready (body_entered.connect) has run.
	ball.setup(pos, dir, true)
	ExplosionSprite.create(self, pos, "muzzle_flash", dir)


func _on_cannonball_water_impacted(impact_pos: Vector2) -> void:
	_displacement_stamps.spawn_impact(impact_pos, 64.0, 2.0)
	for mine: SeaMine in _mines.duplicate():
		mine.check_water_impact(impact_pos)


func _on_mine_dropped(pos: Vector2) -> void:
	var mine: SeaMine = SeaMineScene.instantiate()
	mine.destroyed.connect(_on_mine_destroyed)
	mine.tree_exiting.connect(_on_mine_tree_exiting.bind(mine))
	add_child(mine)
	mine.global_position = pos
	mine.reset_physics_interpolation()
	mine.setup()
	_mines.append(mine)


func _on_mine_destroyed(mine: SeaMine) -> void:
	_displacement_stamps.spawn_impact(mine.global_position, 128.0, 2.5)
	_mines.erase(mine)


func _on_mine_tree_exiting(mine: SeaMine) -> void:
	_mines.erase(mine)


func _update_wave_state(delta: float) -> void:
	## Wave lifecycle:
	##   INTERMISSION → (toast lead-time elapses) → toast shown
	##                → (timer hits zero) → SPAWNING
	##   SPAWNING     → (cadence timer ticks, respect concurrent cap)
	##                → (quota filled) → CLEARING
	##   CLEARING     → (alive count == 0) → INTERMISSION (next wave)
	## Player death does NOT reset wave state — combat resumes on respawn.
	match _wave_phase:
		WavePhase.INTERMISSION:
			_intermission_timer -= delta
			var next_wave: int = _current_wave + 1
			var time_until_start: float = _intermission_timer
			if _toast_shown_for_wave < next_wave and time_until_start <= WAVE_TOAST_LEAD_TIME:
				_wave_toast.show_wave(next_wave)
				_toast_shown_for_wave = next_wave
			if _intermission_timer <= 0.0:
				_begin_wave(next_wave)
		WavePhase.SPAWNING:
			_spawn_cadence_timer -= delta
			if _spawn_cadence_timer <= 0.0:
				if _try_spawn_wave_enemy():
					_spawn_cadence_timer = _current_spawn_interval()
				else:
					# Concurrent cap hit — try again next physics tick.
					_spawn_cadence_timer = 0.1
			if _enemies_spawned_this_wave >= _enemies_to_spawn_this_wave:
				_wave_phase = WavePhase.CLEARING
		WavePhase.CLEARING:
			if _alive_enemy_count() == 0:
				_stats.end_wave()
				# Phase 3.5: if the cleared wave was the last one in the
				# active WaveSet, end the run with a victory instead of
				# rolling into another intermission.
				if wave_set.is_final_wave(_current_wave - 1):
					_wave_phase = WavePhase.ENDED
					Events.run_ended.emit(_stats, true)
				else:
					# Pull the next wave's intermission duration from the
					# WaveSet so designers can tune per-wave breathers.
					_intermission_timer = (_wave_config_for(_current_wave).intermission_duration)
					_wave_phase = WavePhase.INTERMISSION
		WavePhase.ENDED:
			# Run over — no further spawning, ticking, or state changes.
			pass


func _begin_wave(wave: int) -> void:
	_current_wave = wave
	_enemies_spawned_this_wave = 0
	_enemies_to_spawn_this_wave = _wave_config_for(wave).enemies_to_spawn
	_spawn_cadence_timer = 0.0
	_wave_phase = WavePhase.SPAWNING
	_stats.start_wave(wave)


func _wave_config_for(wave: int) -> WaveConfig:
	# WaveSet uses 0-indexed lookups; the in-game wave counter is 1-indexed.
	# get_wave() clamps past the end so play continues with the final wave's
	# tuning indefinitely until Phase 3.5 ships the Victory transition.
	return wave_set.get_wave(maxi(wave - 1, 0))


func _current_max_concurrent() -> int:
	return _wave_config_for(_current_wave).max_concurrent


func _current_spawn_interval() -> float:
	return _wave_config_for(_current_wave).spawn_interval


func _current_speed_mult() -> float:
	return _wave_config_for(_current_wave).speed_mult


func _current_cooldown_mult() -> float:
	return _wave_config_for(_current_wave).cooldown_mult


func _alive_enemy_count() -> int:
	var count: int = 0
	for enemy: EnemyShip in _enemies:
		if is_instance_valid(enemy) and not enemy.is_destroyed():
			count += 1
	return count


func _try_spawn_wave_enemy() -> bool:
	if _alive_enemy_count() >= _current_max_concurrent():
		return false
	var angle: float = randf() * TAU
	var spawn_pos: Vector2 = _ship.global_position + Vector2.from_angle(angle) * spawn_distance
	var enemy: EnemyShip = EnemyShipScene.instantiate()
	enemy.rotation = randf() * TAU
	enemy.cannon_fired.connect(_on_enemy_cannon_fired)
	enemy.destroyed.connect(_on_enemy_destroyed)
	# Single cleanup path: tree_exiting is the only handler that erases from
	# _enemies and frees the wake trail.
	enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.reset_physics_interpolation()
	enemy.setup(_ship)
	enemy.apply_wave_modifiers(_current_speed_mult(), _current_cooldown_mult())
	_enemies.append(enemy)
	_register_enemy_wake(enemy)
	_enemies_spawned_this_wave += 1
	return true


func _on_enemy_tree_exiting(enemy: EnemyShip) -> void:
	_enemies.erase(enemy)
	_unregister_enemy_wake(enemy)


func _register_enemy_wake(enemy: EnemyShip) -> void:
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
	line.sub_viewport = _wake_subviewport
	line.follow_target = enemy
	line.pivot_target = _ship
	_wake_subviewport.add_child(line)
	# Stash the Line2D on the enemy so cleanup can recover it without a
	# Main-side dictionary indirection.
	enemy.set_meta("wake_line", line)


func _unregister_enemy_wake(enemy: EnemyShip) -> void:
	if not enemy.has_meta("wake_line"):
		return
	var line: Line2D = enemy.get_meta("wake_line") as Line2D
	enemy.remove_meta("wake_line")
	if not is_instance_valid(line):
		return
	# Fade the wake trail out instead of snap-clearing — matches the hull
	# fade duration in EnemyShip._destroy().
	line.set_process(false)  # stop appending new points
	var tween: Tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.4)
	tween.tween_callback(line.queue_free)


func _despawn_distant_enemies() -> void:
	for enemy: EnemyShip in _enemies.duplicate():
		if enemy.is_destroyed():
			continue
		if enemy.global_position.distance_to(_ship.global_position) > despawn_distance:
			enemy.queue_free()
			# tree_exiting will fire and clean up _enemies + wake trail.
