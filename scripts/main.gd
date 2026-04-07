extends Node2D
## Scene root — wires the displacement SubViewport to the water shader,
## keeps the displacement viewport tracking the ship, spawns cannonballs,
## and manages enemy ship spawning/despawning, wake trails, and displacement.

const CannonballScene: PackedScene = preload("res://scenes/cannonball.tscn")
const EnemyShipScene: PackedScene = preload("res://scenes/enemy_ship.tscn")
const SeaMineScene: PackedScene = preload("res://scenes/sea_mine.tscn")
const TrailsScript: Script = preload("res://scripts/trails.gd")
const TrailWidthCurve: Curve = preload("res://resources/trail_width_curve.tres")
const TrailGradientTex: Texture2D = preload("res://textures/WaterTrailGradient.png")

@export var max_enemies: int = 4
@export var spawn_interval: float = 8.0
@export var spawn_distance: float = 550.0
@export var despawn_distance: float = 1000.0

var _enemies: Array[EnemyShip] = []
var _mines: Array[SeaMine] = []
var _spawn_timer: float = 2.0
var _wake_distance: float = 0.0
var _last_wake_pos: Vector2 = Vector2.ZERO

@onready var _ship: Ship = $Ship
@onready var _minimap_display: MinimapDisplay = $Minimap/MinimapDisplay
@onready var _displacement_vp: SubViewport = $DisplacementViewport/SubViewport
@onready var _displacement_stamps: Node2D = $DisplacementViewport/SubViewport/Stamps
@onready var _wake_subviewport: SubViewport = $WaterTrail/SubViewport
@onready var _hp_display: HPDisplay = $HPDisplay


func _ready() -> void:
	assert(_ship != null, "Main: Ship node is missing")
	assert(_minimap_display != null, "Main: MinimapDisplay node not found")
	assert(_displacement_vp != null, "Main: DisplacementViewport/SubViewport not found")
	assert(_displacement_stamps != null, "Main: Stamps node not found")
	assert(_wake_subviewport != null, "Main: WaterTrail/SubViewport not found")
	assert(_hp_display != null, "Main: HPDisplay not found")

	# Wire wake trail SubViewport texture to the TrailSprite display.
	$WaterTrail/TrailSprite.texture = _wake_subviewport.get_texture()

	# Wire displacement SubViewport texture to the shared water material.
	# Intentionally shared: all water chunks use the same DisplacementMap.
	# NOT duplicated — uniform updates propagate to every chunk simultaneously.
	var water_mat: ShaderMaterial = $ChunkContainer.water_material as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementMap", _displacement_vp.get_texture())
	water_mat.set_shader_parameter("WakeTrailMap", _wake_subviewport.get_texture())

	_last_wake_pos = _ship.global_position
	_ship.cannon_fired.connect(_on_cannon_fired)
	_ship.mine_dropped.connect(_on_mine_dropped)
	_minimap_display.setup(_ship)
	_hp_display.setup(_ship)


func _process(delta: float) -> void:
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
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_try_spawn_enemy()
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


func _on_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	var ball: Cannonball = CannonballScene.instantiate()
	ball.water_impacted.connect(_on_cannonball_water_impacted)
	add_child(ball)
	ball.setup(pos, dir, false)
	ExplosionSprite.create(self, pos, "muzzle_flash", dir, _ship.velocity * 0.75)


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


func _try_spawn_enemy() -> void:
	if _enemies.size() >= max_enemies:
		return
	var angle: float = randf() * TAU
	var spawn_pos: Vector2 = _ship.global_position + Vector2.from_angle(angle) * spawn_distance
	var enemy: EnemyShip = EnemyShipScene.instantiate()
	enemy.rotation = randf() * TAU
	enemy.cannon_fired.connect(_on_enemy_cannon_fired)
	# Single cleanup path: tree_exiting is the only handler that erases from
	# _enemies and frees the wake trail.
	enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.reset_physics_interpolation()
	enemy.setup(_ship)
	_enemies.append(enemy)
	_register_enemy_wake(enemy)


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
	line.max_length = 90
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
