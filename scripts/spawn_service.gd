class_name SpawnService
extends Node

## Phase 7 Step 36 — Owns runtime instantiation of enemies, mines, and
## cannonballs. Previously lived inline on main.gd. Holds the authoritative
## _enemies / _mines arrays and exposes `alive_enemy_count()` for the
## WaveDirector clearing check.
##
## Cross-coupling: subscribes to Events.cannonball_water_impact so the mine
## list can test each mine's proximity to the impact. **Reentrancy guard:**
## iterating via _mines.duplicate() is required — SeaMine.check_water_impact
## can synchronously remove mines from the array via the destroyed →
## _on_mine_destroyed chain, and detonation can also recurse via
## SeaMine.schedule_chain_detonation (Phase 6 Step 34g made that path safe
## at the target side, but the caller still needs the snapshot).

const CannonballScene: PackedScene = preload("res://scenes/cannonball.tscn")
const EnemyShipScene: PackedScene = preload("res://scenes/enemy_ship.tscn")
const SeaMineScene: PackedScene = preload("res://scenes/sea_mine.tscn")

@export var spawn_distance: float = 550.0
@export var despawn_distance: float = 1000.0

var _enemies: Array[EnemyShip] = []
var _mines: Array[SeaMine] = []
var _ship: Ship = null
var _water_effects: WaterEffectsManager = null
var _stats: RunStats = null


func _ready() -> void:
	Events.cannonball_water_impact.connect(_on_cannonball_water_impact)


func setup(ship: Ship, water_effects: WaterEffectsManager, stats: RunStats) -> void:
	assert(ship != null, "SpawnService.setup: ship is null")
	assert(water_effects != null, "SpawnService.setup: water_effects is null")
	assert(stats != null, "SpawnService.setup: stats is null")
	_ship = ship
	_water_effects = water_effects
	_stats = stats


func _physics_process(_delta: float) -> void:
	_despawn_distant_enemies()


func alive_enemy_count() -> int:
	var count: int = 0
	for enemy: EnemyShip in _enemies:
		if is_instance_valid(enemy) and not enemy.is_destroyed():
			count += 1
	return count


func get_enemies() -> Array[EnemyShip]:
	return _enemies


func get_mines() -> Array[SeaMine]:
	return _mines


## Connected to Ship.cannon_fired in main.gd.
func spawn_player_cannonball(pos: Vector2, dir: Vector2) -> void:
	var ball: Cannonball = CannonballScene.instantiate()
	ball.water_impacted.connect(_water_effects.on_cannonball_water_impact)
	ball.hit_registered.connect(_on_player_ball_hit)
	add_child(ball)
	ball.setup(pos, dir, false)
	_stats.register_shot_fired()
	Events.explosion_requested.emit(pos, &"muzzle_flash", dir, _ship.velocity * 0.75)


## Connected to Ship.mine_dropped in main.gd.
func spawn_mine(pos: Vector2) -> void:
	var mine: SeaMine = SeaMineScene.instantiate()
	mine.destroyed.connect(_on_mine_destroyed)
	mine.tree_exiting.connect(_on_mine_tree_exiting.bind(mine))
	add_child(mine)
	mine.global_position = pos
	mine.reset_physics_interpolation()
	mine.setup()
	_mines.append(mine)


## Connected to WaveDirector.spawn_requested in main.gd.
func spawn_wave_enemy(config: WaveConfig) -> void:
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
	enemy.apply_wave_modifiers(config.speed_mult, config.cooldown_mult)
	_enemies.append(enemy)
	_water_effects.register_enemy_wake(enemy)


func _on_player_ball_hit() -> void:
	_stats.register_shot_hit()


func _on_enemy_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	var ball: Cannonball = CannonballScene.instantiate()
	ball.water_impacted.connect(_water_effects.on_cannonball_water_impact)
	add_child(ball)
	# add_child must precede setup so _ready (body_entered.connect) has run.
	ball.setup(pos, dir, true)
	Events.explosion_requested.emit(pos, &"muzzle_flash", dir, Vector2.ZERO)


func _on_enemy_destroyed(_enemy: EnemyShip, by_mine: bool) -> void:
	_stats.register_enemy_destroyed(by_mine)


func _on_enemy_tree_exiting(enemy: EnemyShip) -> void:
	_enemies.erase(enemy)
	_water_effects.unregister_enemy_wake(enemy)


func _on_mine_destroyed(mine: SeaMine) -> void:
	_water_effects.on_mine_explosion(mine.global_position)
	_mines.erase(mine)


func _on_mine_tree_exiting(mine: SeaMine) -> void:
	_mines.erase(mine)


func _on_cannonball_water_impact(pos: Vector2) -> void:
	# Snapshot-before-iterate: SeaMine.check_water_impact can synchronously
	# trigger detonation chains that mutate _mines (via destroyed signals and
	# tree_exiting cleanup). See Phase 6 retro + Phase 7 Step 36 notes.
	for mine: SeaMine in _mines.duplicate():
		if is_instance_valid(mine):
			mine.check_water_impact(pos)


func _despawn_distant_enemies() -> void:
	if _ship == null:
		return
	for enemy: EnemyShip in _enemies.duplicate():
		if enemy.is_destroyed():
			continue
		if enemy.global_position.distance_to(_ship.global_position) > despawn_distance:
			enemy.queue_free()
			# tree_exiting fires and cleans up _enemies + wake trail.
